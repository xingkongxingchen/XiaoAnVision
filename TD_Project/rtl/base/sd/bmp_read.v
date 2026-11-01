module bmp_read #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer SD_READ_TIMEOUT_MS = 500,
    parameter integer SD_REINIT_TIMEOUT_MS = 2000
)(
    input                       clk,
    input                       rst,
    output                      ready,
    output reg                  load_done,
    output reg                  load_error,
    output reg [3:0]            error_code,
    output                      sd_recover_reset,
    output [31:0]              header_file_len,
    output [31:0]              header_pixel_offset,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);

localparam ST_IDLE      = 3'd0;
localparam ST_SCAN      = 3'd1;
localparam ST_LOAD_HDR  = 3'd2;
localparam ST_LOAD_WAIT = 3'd3;
localparam ST_LOAD_DATA = 3'd4;
localparam ST_LOAD_ARM  = 3'd5;
localparam ST_SD_RESET  = 4'd6;
localparam ST_REINIT    = 4'd7;
localparam ST_HALT      = 4'd8;
localparam integer TIMEOUT_CYCLES = (CLK_FREQ_HZ / 1000) * SD_READ_TIMEOUT_MS;
localparam integer REINIT_CYCLES = (CLK_FREQ_HZ / 1000) * SD_REINIT_TIMEOUT_MS;
reg [31:0] timeout_count;
reg [3:0] previous_state;
reg [3:0] state;
reg timeout_was_scan;
reg scan_retry_used;
wire timed_state = (state == ST_SCAN) || (state == ST_LOAD_HDR) ||
                   (state == ST_LOAD_DATA) || (state == ST_LOAD_WAIT) ||
                   (state == ST_LOAD_ARM);
wire timeout_hit = timed_state && (state == previous_state) &&
                   !sd_sec_read_end && (timeout_count >= TIMEOUT_CYCLES - 1);
assign sd_recover_reset = (state == ST_SD_RESET);

// Bound EACH sector/ACK wait, not the total multi-sector image duration.
always @(posedge clk or posedge rst) begin
    if (rst) begin timeout_count <= 0; previous_state <= ST_IDLE; end
    else begin
        previous_state <= state;
        if (state != previous_state || sd_sec_read_end || state == ST_IDLE || state == ST_HALT)
            timeout_count <= 0;
        else if (timeout_count != 32'hffffffff) timeout_count <= timeout_count + 1'b1;
    end
end

// write_req_ack originates in mem_clk. Only the final synchronizer stage
// may control this SD-clock FSM; hold request until the level is observed.
reg [2:0] write_ack_sync;
always @(posedge clk or posedge rst) begin
    if (rst) write_ack_sync <= 3'b000;
    else write_ack_sync <= {write_ack_sync[1:0], write_req_ack};
end

reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [15:0] bit_count;
reg [31:0] compression;
reg [31:0] dib_size;
reg [15:0] planes;
reg [31:0] pixel_count;

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;

wire header_match;
wire header_format_ok;
wire header_bounds_ok;
wire [31:0] expected_pixels = bmp_width * bmp_height;
wire [34:0] pixel_end = {3'd0, pixel_offset} + ({3'd0, expected_pixels} * 35'd3);
wire bmp_data_valid;
reg [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_match;
wire [31:0] next_scan_sector_if_miss;
reg [32:0] scan_jump;
reg scan_jump_in_range;
// Header length is complete at byte 5. Pipeline the scan arithmetic while
// receiving the remaining bytes; only consume it after the full 512-byte header.
always @(posedge clk or posedge rst) begin
    if (rst) begin file_sector_count <= 0; scan_jump <= 0; scan_jump_in_range <= 0; end
    else begin
        file_sector_count <= (file_len >> 9) + ((file_len[8:0] != 0) ? 32'd1 : 32'd0);
        scan_jump <= {1'b0, scan_sector} + {1'b0, file_sector_count};
        scan_jump_in_range <= (scan_jump <= {1'b0, scan_max_sector});
    end
end
// MiCu bad-BMP fast skip, bounded so a corrupt length cannot leave the scan range.
wire safe_bad_skip = (rd_cnt == 512) && (header_0 == "B") && (header_1 == "M") &&
                     (dib_size >= 40) && (planes == 1) && (pixel_offset >= 54) &&
                     (pixel_offset < file_len) && (file_sector_count > 1) &&
                     scan_jump_in_range;

assign ready = (state == ST_IDLE);
assign header_file_len = file_len;
assign header_pixel_offset = pixel_offset;
assign header_format_ok = (header_0 == "B") &&
                      (header_1 == "M") &&
                      (dib_size >= 32'd40) && (planes == 16'd1) &&
                      (width == {16'd0, bmp_width}) &&
                      (height == {16'd0, bmp_height}) &&
                      (bit_count    == 16'd24) &&
                      (compression  == 32'd0);
// Lecture 5: matching geometry alone does not prove a usable BMP.
assign header_bounds_ok = (pixel_offset >= 32'd54) &&
                          (pixel_offset < file_len) &&
                          (expected_pixels != 0) &&
                          (pixel_end <= {3'd0, file_len});
assign header_match = header_format_ok && header_bounds_ok && (rd_cnt == 10'd512);
assign bmp_data_valid = (sd_sec_read_data_valid == 1'b1) &&
                        (bmp_len_cnt >= pixel_offset) &&
                        ({3'd0, bmp_len_cnt} < pixel_end);
assign next_scan_sector_if_match = scan_jump[31:0];
assign next_scan_sector_if_miss  = safe_bad_skip ? scan_jump[31:0] : scan_sector + 32'd1;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR) || (state == ST_LOAD_DATA)) begin
        if (sd_sec_read_end)
            rd_cnt <= 10'd0;
        else if (sd_sec_read_data_valid && rd_cnt != 10'd1023)
            rd_cnt <= rd_cnt + 10'd1;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
        dib_size     <= 32'd0;
        planes       <= 16'd0;
    end else if (((state == ST_IDLE) && (scan_start || load_start)) ||
                 ((state == ST_SCAN) && sd_sec_read_end)) begin
        header_0 <= 0;
        header_1 <= 0;
        file_len <= 0;
        pixel_offset <= 0;
        width <= 0;
        height <= 0;
        bit_count <= 0;
        compression <= 0;
        dib_size <= 0;
        planes <= 0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : header_0 <= sd_sec_read_data;
            10'd1 : header_1 <= sd_sec_read_data;

            10'd2 : file_len[7:0] <= sd_sec_read_data;
            10'd3 : file_len[15:8] <= sd_sec_read_data;
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;

            10'd14: dib_size[7:0] <= sd_sec_read_data;
            10'd15: dib_size[15:8] <= sd_sec_read_data;
            10'd16: dib_size[23:16] <= sd_sec_read_data;
            10'd17: dib_size[31:24] <= sd_sec_read_data;

            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: height[23:16] <= sd_sec_read_data;
            10'd25: height[31:24] <= sd_sec_read_data;

            10'd26: planes[7:0] <= sd_sec_read_data;
            10'd27: planes[15:8] <= sd_sec_read_data;

            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;

            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

// Count completed RGB pixels, not bytes or sector-end indications.
always @(posedge clk or posedge rst) begin
    if (rst) pixel_count <= 32'd0;
    else if (state != ST_LOAD_DATA) pixel_count <= 32'd0;
    else if (bmp_data_valid && bmp_byte_idx == 2'd2)
        pixel_count <= pixel_count + 32'd1;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_byte_idx <= 2'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid)
            bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : (bmp_byte_idx + 2'd1);
    end else begin
        bmp_byte_idx <= 2'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid) begin
            case (bmp_byte_idx)
                2'd0: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[7:0]  <= sd_sec_read_data;
                end
                2'd1: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[15:8] <= sd_sec_read_data;
                end
                2'd2: begin
                    bmp_data_wr_en  <= 1'b1;
                    bmp_data[23:16] <= sd_sec_read_data;
                end
                default: begin
                    bmp_data_wr_en <= 1'b0;
                end
            endcase
        end else begin
            bmp_data_wr_en <= 1'b0;
        end
    end else begin
        bmp_data_wr_en <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        load_done         <= 1'b0;
        load_error        <= 1'b0;
        error_code        <= 4'd0;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        timeout_was_scan <= 1'b0;
        scan_retry_used <= 1'b0;
    end else if (!sd_init_done && state == ST_IDLE) begin
        state             <= ST_IDLE;
        load_done         <= 1'b0;
        load_error        <= 1'b0;
        error_code        <= 4'd0;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
    end else begin
        scan_found_valid <= 1'b0;
        load_done <= 1'b0;
        load_error <= 1'b0;

        if (timeout_hit) begin
            timeout_was_scan <= (state == ST_SCAN);
            sd_sec_read <= 1'b0;
            write_req <= 1'b0;
            error_code <= 4'd6;
            state <= ST_SD_RESET;
        end else case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_retry_used  <= 1'b0;
                    scan_done        <= 1'b0;
                    scan_found_total <= 3'd0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                end else if (load_start) begin
                    error_code          <= 4'd0;
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    scan_retry_used <= 1'b0;

                    if (header_match) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 3'd1;

                        if ((scan_found_total + 3'd1 >= scan_target_count) || !scan_jump_in_range) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end
                    end else begin
                        if (scan_sector >= scan_max_sector) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                        end
                    end
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_match) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        load_error <= 1'b1;
                        error_code <= (rd_cnt != 10'd512) ? 4'd3 :
                                      (!header_format_ok ? 4'd1 : 4'd2);
                        state <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_ack_sync[2]) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_ARM;
                end
            end

            ST_LOAD_ARM: begin
                state_code <= 4'd3;
                // ACK falls when the memory-side FIFO clear has been released.
                // Do not request pixel data while that handshake is active.
                if (!write_ack_sync[2]) state <= ST_LOAD_DATA;
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (rd_cnt != 10'd512) begin
                        load_error <= 1'b1;
                        error_code <= 4'd3;
                        state <= ST_IDLE;
                    end else if ({3'd0, bmp_len_cnt} >= pixel_end) begin
                        // Do not wait for a memory frame the source never produced.
                        load_done <= (pixel_count == expected_pixels);
                        load_error <= (pixel_count != expected_pixels);
                        error_code <= (pixel_count == expected_pixels) ? 4'd0 : 4'd4;
                        state <= ST_IDLE;
                    end else begin
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end
                end
            end

            ST_SD_RESET: begin
                state_code <= 4'd6;
                sd_sec_read <= 1'b0;
                write_req <= 1'b0;
                // Reset the SD transport only; no SDRAM/video/global reset.
                if (state == previous_state && timeout_count >= 16) state <= ST_REINIT;
            end

            ST_REINIT: begin
                state_code <= 4'd6;
                if (sd_init_done) begin
                    if (timeout_was_scan && !scan_retry_used) begin
                        scan_retry_used <= 1'b1;
                        state <= ST_SCAN;
                    end else begin
                        load_error <= 1'b1;
                        error_code <= 4'd6;
                        if (timeout_was_scan) scan_done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end else if (state == previous_state && timeout_count >= REINIT_CYCLES - 1) begin
                    load_error <= 1'b1;
                    error_code <= 4'd7;
                    state <= ST_HALT;
                end
            end

            ST_HALT: begin
                state_code <= 4'he;
                sd_sec_read <= 1'b0;
                write_req <= 1'b0;
                // Card did not reinitialize: preserve frame, K4 required.
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
                load_error  <= 1'b1;
                error_code  <= 4'd5;
            end
        endcase
    end
end

endmodule
