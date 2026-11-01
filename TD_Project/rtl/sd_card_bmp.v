`timescale 1ns/1ps

module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ        = 100_000_000,
    parameter integer LONG_PRESS_MS      = 1000,
    parameter integer AUTO_PLAY_MS       = 3000,
    parameter integer SD_READ_TIMEOUT_MS = 500,
    parameter integer SD_REINIT_TIMEOUT_MS = 2000,
    parameter [31:0]  SCAN_START_SECTOR  = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR    = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT  = 3'd4
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    output [3:0]                state_code,
    output [1:0]                current_image_index,
    output [2:0]                image_found_count,
    output                      auto_play_enabled,
    output                      load_busy_status,
    output [3:0]                trace_load_status,
    output                      trace_load_failed,
    output [3:0]                trace_error_code,
    output [31:0]               trace_file_len,
    output [31:0]               trace_pixel_offset,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             bmp_load_done;
wire             bmp_load_error;
wire             sd_recover_reset;
wire [3:0]       bmp_error_code;
reg              sd_was_ready;
reg              transport_failed;
reg [3:0]        recovery_error;
reg [31:0]       memory_wait_count;
localparam integer WAIT_CYCLES = (CLK_FREQ_HZ / 1000) * SD_READ_TIMEOUT_MS;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;
wire [3:0]       loader_state_code;

wire next_event;
wire prev_event;
wire auto_toggle_event;
wire step_next;
wire step_prev;
wire auto_play_en;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg [2:0]        img_found_count;
reg [1:0]        img_idx;
reg [1:0]        load_idx;
reg [1:0]        pending_buf_idx;
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg              load_busy;
reg              source_done_seen;
reg              write_done_seen;
reg              retry_used;
reg              header_failed;

reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;
wire memory_timeout = load_busy && source_done_seen && !write_done_seen &&
                      !write_finish_pulse && (memory_wait_count >= WAIT_CYCLES - 1);
wire load_fault = bmp_load_error || memory_timeout;
wire [3:0] load_fault_code = memory_timeout ? 4'd8 : bmp_error_code;

assign write_en             = bmp_data_wr_en;
assign write_data           = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign write_finish_pulse   = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
assign current_image_index  = img_idx;
assign image_found_count    = img_found_count;
assign auto_play_enabled    = auto_play_en;
assign state_code           = header_failed ? 4'he : loader_state_code;
assign load_busy_status     = load_busy;
assign trace_load_status    = {load_idx, source_done_seen, write_done_seen};
assign trace_load_failed    = header_failed;
assign trace_error_code     = header_failed ? recovery_error : bmp_error_code;

always @(posedge clk or posedge rst) begin
    if (rst) memory_wait_count <= 0;
    else if (!load_busy || !source_done_seen || write_done_seen || write_finish_pulse || load_start_pulse)
        memory_wait_count <= 0;
    else if (memory_wait_count < WAIT_CYCLES) memory_wait_count <= memory_wait_count + 1'b1;
end

slideshow_key_router #(
    .CLK_FREQ_HZ  (CLK_FREQ_HZ),
    .DEBOUNCE_MS  (20),
    .LONG_PRESS_MS(LONG_PRESS_MS)
) u_slideshow_key_router (
    .clk              (clk),
    .rst_n            (~rst),
    .key_next_n       (key_next),
    .key_mode_n       (key_auto),
    .next_event       (next_event),
    .auto_toggle_event(auto_toggle_event),
    .prev_event       (prev_event)
);

slideshow_policy #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .AUTO_PLAY_MS(AUTO_PLAY_MS)
) u_slideshow_policy (
    .clk              (clk),
    .rst_n            (~rst),
    .scan_ready       (scan_done),
    .image_count      (img_found_count),
    .display_valid    (display_valid),
    .load_busy        (load_busy),
    .loader_ready     (bmp_ready && !transport_failed),
    .next_event       (next_event && first_image_committed),
    .prev_event       (prev_event),
    .auto_toggle_event(auto_toggle_event),
    .step_next        (step_next),
    .step_prev        (step_prev),
    .auto_play_en     (auto_play_en)
);

function [1:0] next_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0, 3'd1: next_index_limited = 2'd0;
            3'd2: next_index_limited = (cur == 2'd1) ? 2'd0 : cur + 2'd1;
            3'd3: next_index_limited = (cur == 2'd2) ? 2'd0 : cur + 2'd1;
            default: next_index_limited = (cur == 2'd3) ? 2'd0 : cur + 2'd1;
        endcase
    end
endfunction

function [1:0] prev_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0, 3'd1: prev_index_limited = 2'd0;
            3'd2: prev_index_limited = (cur == 2'd0) ? 2'd1 : cur - 2'd1;
            3'd3: prev_index_limited = (cur == 2'd0) ? 2'd2 : cur - 2'd1;
            default: prev_index_limited = (cur == 2'd0) ? 2'd3 : cur - 2'd1;
        endcase
    end
endfunction

function [31:0] sector_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: sector_lut = img_sector0;
            2'd1: sector_lut = img_sector1;
            2'd2: sector_lut = img_sector2;
            2'd3: sector_lut = img_sector3;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        img_found_count       <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        load_busy             <= 1'b0;
        source_done_seen      <= 1'b0;
        write_done_seen       <= 1'b0;
        retry_used            <= 1'b0;
        header_failed         <= 1'b0;
        display_valid         <= 1'b0;
        sd_was_ready          <= 1'b0;
        transport_failed      <= 1'b0;
        recovery_error        <= 4'd0;
    end else begin
        if (sd_init_done) sd_was_ready <= 1'b1;
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;

        if (!sd_init_done && !sd_was_ready) begin
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            write_done_seen       <= 1'b0;
            retry_used            <= 1'b0;
            header_failed         <= 1'b0;
            display_valid         <= 1'b0;
        end else begin
            if (scan_found_valid) begin
                case (img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    default: ;
                endcase
                if (img_found_count < 3'd4)
                    img_found_count <= img_found_count + 3'd1;
            end

            // The retry's FIFO-reset handshake starts a fresh transaction;
            // do not carry a late completion from the rejected attempt.
            if (load_busy && write_req) begin
                source_done_seen <= 1'b0;
                write_done_seen <= 1'b0;
            end
            if (load_busy && !write_req && bmp_load_done)
                source_done_seen <= 1'b1;
            if (load_busy && !write_req && write_finish_pulse)
                write_done_seen <= 1'b1;

            // MiCu lecture 5: retry a rejected header/short frame once.
            // A new write request clears the pending FIFO; never commit failure.
            if (load_busy && load_fault) begin
                recovery_error <= load_fault_code;
                source_done_seen <= 1'b0;
                write_done_seen  <= 1'b0;
                if (load_fault_code == 4'd7) begin
                    load_busy <= 1'b0;
                    header_failed <= 1'b1;
                    transport_failed <= 1'b1;
                end else if (!retry_used) begin
                    retry_used       <= 1'b1;
                    load_start_pulse <= 1'b1;
                end else begin
                    load_busy     <= 1'b0;
                    header_failed <= 1'b1;
                end
            end else if (load_busy && (source_done_seen || bmp_load_done) &&
                         (write_done_seen || write_finish_pulse)) begin
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
                header_failed         <= 1'b0;
                disp_buf_idx          <= pending_buf_idx;
                img_idx               <= load_idx;
                display_valid         <= 1'b1;
                first_image_committed <= 1'b1;
            end

            if (bmp_load_error && !load_busy) begin
                header_failed <= 1'b1;
                recovery_error <= bmp_error_code;
                if (bmp_error_code == 4'd7) transport_failed <= 1'b1;
            end

            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                write_done_seen       <= 1'b0;
                retry_used            <= 1'b0;
                header_failed         <= 1'b0;
            end else begin
                if (scan_done && !first_image_committed && bmp_ready && !load_busy && !bmp_load_error &&
                    (!header_failed || next_event) && !transport_failed &&
                    img_found_count != 3'd0) begin
                    load_idx         <= 2'd0;
                    load_sector      <= img_sector0;
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    retry_used       <= 1'b0;
                    header_failed    <= 1'b0;
                end else if (step_next) begin
                    // After an exhausted failure advance past that target, not
                    // past the still-displayed old frame (which would retry forever).
                    load_idx         <= next_index_limited((header_failed && auto_play_en) ? load_idx : img_idx, img_found_count);
                    load_sector      <= sector_lut(next_index_limited((header_failed && auto_play_en) ? load_idx : img_idx, img_found_count));
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    retry_used       <= 1'b0;
                    header_failed    <= 1'b0;
                end else if (step_prev) begin
                    load_idx         <= prev_index_limited(img_idx, img_found_count);
                    load_sector      <= sector_lut(prev_index_limited(img_idx, img_found_count));
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    write_done_seen  <= 1'b0;
                    retry_used       <= 1'b0;
                    header_failed    <= 1'b0;
                end
            end
        end
    end
end

// The existing LUT now stores file IDs; FAT cluster/size tables live in u_volume.
fat32_bmp_read #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .SD_READ_TIMEOUT_MS(SD_READ_TIMEOUT_MS),
           .SD_REINIT_TIMEOUT_MS(SD_REINIT_TIMEOUT_MS)) bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),
    .load_done              (bmp_load_done),
    .load_error             (bmp_load_error),
    .error_code             (bmp_error_code),
    .sd_recover_reset       (sd_recover_reset),
    .header_file_len        (trace_file_len),
    .header_pixel_offset    (trace_pixel_offset),
    .scan_start             (scan_start_pulse),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),
    .load_start             (load_start_pulse),
    .load_sector            (load_sector),
    .sd_init_done           (sd_init_done),
    .state_code             (loader_state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

sd_card_top sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst | sd_recover_reset),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule
