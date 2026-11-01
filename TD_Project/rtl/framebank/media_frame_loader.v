`timescale 1ns/1ps

module media_frame_loader #(
    parameter integer ADDR_WIDTH = 21,
    parameter integer IMAGE_WORDS = 307200,
    parameter integer FIFO_DEPTH = 512,
    parameter integer BURST_SIZE = 128,
    parameter integer STALL_TIMEOUT = 65535,
    parameter integer FRAME_WIDTH = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer BMP_BOTTOM_UP = 1,
    parameter integer DYNAMIC_ORIENTATION = 0
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  load_start,
    input  wire                  bmp_top_down,
    input  wire [1:0]            image_index,
    input  wire                  pixel_valid,
    input  wire [23:0]           pixel_rgb,
    input  wire                  frame_commit,
    input  wire [7:0]            decode_error,
    output wire                  load_busy,
    output reg                   load_done,
    output reg  [3:0]            image_complete,
    output reg  [7:0]            memory_error,
    input  wire                  controller_init_done,
    input  wire                  controller_busy,
    input  wire                  refresh_active,
    output reg                   app_wr_en,
    output reg  [ADDR_WIDTH-1:0] app_wr_addr,
    output reg  [3:0]            app_wr_mask,
    output reg  [31:0]           app_wr_data
);
    localparam ERR_NONE          = 8'h00;
    localparam ERR_NOT_ACTIVE    = 8'h41;
    localparam ERR_FIFO_OVERFLOW = 8'h42;
    localparam ERR_PIXEL_COUNT   = 8'h43;
    localparam ERR_DECODE        = 8'h44;
    localparam ERR_SHORT_FRAME   = 8'h45;
    localparam ERR_WRITE_STALL   = 8'h46;

    localparam integer PTR_WIDTH = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);
    localparam integer PIXEL_COUNT_WIDTH = (IMAGE_WORDS < 2) ? 1 : $clog2(IMAGE_WORDS+1);
    localparam integer STALL_COUNT_WIDTH = (STALL_TIMEOUT < 2) ? 1 : $clog2(STALL_TIMEOUT+1);
    localparam [PTR_WIDTH:0] EFFECTIVE_BURST =
        (BURST_SIZE < FIFO_DEPTH) ? BURST_SIZE : FIFO_DEPTH;
    localparam [ADDR_WIDTH-1:0] BANK0_BASE = 0;
    localparam [ADDR_WIDTH-1:0] BANK1_BASE = IMAGE_WORDS;
    localparam [ADDR_WIDTH-1:0] BANK2_BASE = IMAGE_WORDS * 2;
    localparam [ADDR_WIDTH-1:0] BANK3_BASE = IMAGE_WORDS * 3;

    reg active;
    reg bottom_up;
    wire input_bottom_up=DYNAMIC_ORIENTATION ? !bmp_top_down : BMP_BOTTOM_UP;
    reg [1:0] active_image;
    reg commit_seen;
    reg [PIXEL_COUNT_WIDTH-1:0] pixels_received;
    reg [PIXEL_COUNT_WIDTH-1:0] pixels_written;
    reg received_full;
    reg written_full;
    reg [ADDR_WIDTH-1:0] row_address;
    reg [11:0] column;
    reg [STALL_COUNT_WIDTH-1:0] stall_count;
    reg [31:0] fifo_mem [0:FIFO_DEPTH-1]; /* fehdl force_ram=1, ram_style="bram" */
    reg [PTR_WIDTH-1:0] wr_ptr;
    reg [PTR_WIDTH-1:0] rd_ptr;
    reg [PTR_WIDTH-1:0] ram_wr_address;
    reg [PTR_WIDTH-1:0] ram_rd_address;
    reg [31:0] ram_wr_data;
    reg ram_wr_valid;
    reg [PTR_WIDTH:0] fifo_count;
    reg burst_active;
    reg [PTR_WIDTH:0] burst_remaining;
    wire pop_allowed;
    wire push_allowed;
    wire start_burst;
    wire [PTR_WIDTH:0] next_burst_words;

    assign load_busy = active;
    // The inherited controller consumes a continuous App_wr_en burst and
    // handles busy/refresh internally. Those status outputs are not per-word
    // ready signals and must not split an active write burst.
    assign start_burst = active && controller_init_done && !burst_active &&
                         fifo_count != 0 &&
                         (fifo_count >= EFFECTIVE_BURST || commit_seen);
    assign next_burst_words = (fifo_count >= EFFECTIVE_BURST) ?
                              EFFECTIVE_BURST : fifo_count;
    assign pop_allowed = active && controller_init_done && burst_active &&
                         fifo_count != 0;
    assign push_allowed = active && pixel_valid &&
                          (fifo_count < FIFO_DEPTH || pop_allowed);

    // RAM contents do not need reset; pointers/count invalidate old contents.
    // Keep the synchronous RAM ports outside the control reset tree so TD can
    // infer BRAM instead of a reset-gated distributed memory (100 MHz STA).
    wire transfer_ok = decode_error == 0 &&
                       !(pixel_valid && (received_full || !push_allowed));
    // Accept writes on the original rising edge, then commit to RAM on the
    // falling edge. An empty FIFO cannot pop that same rising edge, so every
    // accepted word is stored before its earliest possible read next cycle.
    // This separates all RAM write-port inputs from their sampling edge.
    always @(posedge clk) begin
        ram_wr_address <= wr_ptr;
        ram_wr_data <= {8'h00, pixel_rgb};
        if (pop_allowed && transfer_ok)
            app_wr_data <= fifo_mem[ram_rd_address];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ram_wr_valid <= 1'b0;
        else ram_wr_valid <= push_allowed && transfer_ok;
    end
    always @(negedge clk) begin
        if (ram_wr_valid)
            fifo_mem[ram_wr_address] <= ram_wr_data;
    end
    // Keep this address register outside the RAM: its independent reset
    // prevents folding into the RAM's read-address latch and moving the
    // original rising-edge read enable onto a half-cycle falling-edge path.
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) ram_rd_address <= 0;
        else ram_rd_address <= rd_ptr;
    end

    function [ADDR_WIDTH-1:0] bank_base;
        input [1:0] index;
        begin
            case (index)
                2'd0: bank_base = BANK0_BASE;
                2'd1: bank_base = BANK1_BASE;
                2'd2: bank_base = BANK2_BASE;
                default: bank_base = BANK3_BASE;
            endcase
        end
    endfunction

    task fail_load;
        input [7:0] code;
        begin
            memory_error <= code;
            active <= 1'b0;
            bottom_up <= BMP_BOTTOM_UP;
            burst_active <= 1'b0;
            burst_remaining <= 0;
            load_done <= 1'b1;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            active_image <= 2'd0;
            commit_seen <= 1'b0;
            pixels_received <= 32'd0;
            pixels_written <= 32'd0;
            received_full <= 1'b0;
            written_full <= 1'b0;
            row_address <= 0;
            column <= 0;
            stall_count <= 32'd0;
            wr_ptr <= {PTR_WIDTH{1'b0}};
            rd_ptr <= {PTR_WIDTH{1'b0}};
            fifo_count <= {(PTR_WIDTH+1){1'b0}};
            burst_active <= 1'b0;
            burst_remaining <= 0;
            load_done <= 1'b0;
            image_complete <= 4'd0;
            memory_error <= ERR_NONE;
            app_wr_en <= 1'b0;
            app_wr_addr <= {ADDR_WIDTH{1'b0}};
            app_wr_mask <= 4'b0000;
        end else begin
            load_done <= 1'b0;
            app_wr_en <= 1'b0;

            if (load_start && !active) begin
                active <= 1'b1;
                active_image <= image_index;
                commit_seen <= 1'b0;
                pixels_received <= 32'd0;
                pixels_written <= 32'd0;
                received_full <= 1'b0;
                written_full <= 1'b0;
                bottom_up <= input_bottom_up;
                row_address <= bank_base(image_index) + (input_bottom_up ? (FRAME_HEIGHT-1)*FRAME_WIDTH : 0);
                column <= 0;
                stall_count <= 32'd0;
                wr_ptr <= {PTR_WIDTH{1'b0}};
                rd_ptr <= {PTR_WIDTH{1'b0}};
                fifo_count <= {(PTR_WIDTH+1){1'b0}};
                burst_active <= 1'b0;
                burst_remaining <= 0;
                memory_error <= ERR_NONE;
                case (image_index)
                    2'd0: image_complete[0] <= 1'b0;
                    2'd1: image_complete[1] <= 1'b0;
                    2'd2: image_complete[2] <= 1'b0;
                    default: image_complete[3] <= 1'b0;
                endcase
            end

            if (active) begin
                if (decode_error != 0) begin
                    fail_load(ERR_DECODE);
                end else if (pixel_valid && received_full) begin
                    fail_load(ERR_PIXEL_COUNT);
                end else if (pixel_valid && !push_allowed) begin
                    fail_load(ERR_FIFO_OVERFLOW);
                end else begin
                    if (start_burst) begin
                        burst_active <= 1'b1;
                        burst_remaining <= next_burst_words;
                    end

                    if (push_allowed) begin
                        wr_ptr <= wr_ptr + 1'b1;
                        pixels_received <= pixels_received + 1'b1;
                        if (pixels_received == IMAGE_WORDS-1)
                            received_full <= 1'b1;
                    end

                    if (pop_allowed) begin
                        app_wr_en <= 1'b1;
                        // BMP file rows are bottom-up. Each 640-word row contains
                        // exactly five 128-word bursts; no burst crosses a row.
                        app_wr_addr <= row_address + column;
                        if (column == FRAME_WIDTH-1) begin
                            column <= 0;
                            row_address <= bottom_up ? row_address-FRAME_WIDTH : row_address+FRAME_WIDTH;
                        end else column <= column + 1'b1;
                        app_wr_mask <= 4'b0000;
                        rd_ptr <= rd_ptr + 1'b1;
                        pixels_written <= pixels_written + 1'b1;
                        if (pixels_written == IMAGE_WORDS-1)
                            written_full <= 1'b1;
                        stall_count <= 32'd0;
                        if (burst_remaining == 1) begin
                            burst_active <= 1'b0;
                            burst_remaining <= 0;
                        end else begin
                            burst_remaining <= burst_remaining - 1'b1;
                        end
                    end else if (fifo_count != 0 &&
                                 (commit_seen || fifo_count >= EFFECTIVE_BURST)) begin
                        if (stall_count == STALL_TIMEOUT)
                            fail_load(ERR_WRITE_STALL);
                        else
                            stall_count <= stall_count + 1'b1;
                    end else begin
                        stall_count <= 32'd0;
                    end

                    case ({push_allowed, pop_allowed})
                        2'b10: fifo_count <= fifo_count + 1'b1;
                        2'b01: fifo_count <= fifo_count - 1'b1;
                        default: fifo_count <= fifo_count;
                    endcase

                    if (frame_commit)
                        commit_seen <= 1'b1;

                    if (commit_seen && fifo_count == 0 && !pop_allowed &&
                        !burst_active) begin
                        if (!received_full || !written_full) begin
                            fail_load(ERR_SHORT_FRAME);
                        end else begin
                            case (active_image)
                                2'd0: image_complete[0] <= 1'b1;
                                2'd1: image_complete[1] <= 1'b1;
                                2'd2: image_complete[2] <= 1'b1;
                                default: image_complete[3] <= 1'b1;
                            endcase
                            active <= 1'b0;
                            load_done <= 1'b1;
                        end
                    end
                end
            end else if (pixel_valid) begin
                memory_error <= ERR_NOT_ACTIVE;
            end
        end
    end
endmodule
