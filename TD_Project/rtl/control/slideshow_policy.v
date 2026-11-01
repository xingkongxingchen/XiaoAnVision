`timescale 1ns/1ps

// MiCu-style policy layer: converts user/periodic events into single-step
// commands. Requests are retained while the image loader is busy.
module slideshow_policy #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer AUTO_PLAY_MS = 3000
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       scan_ready,
    input  wire [2:0] image_count,
    input  wire       display_valid,
    input  wire       load_busy,
    input  wire       loader_ready,
    input  wire       next_event,
    input  wire       prev_event,
    input  wire       auto_toggle_event,
    output reg        step_next,
    output reg        step_prev,
    output reg        auto_play_en
);
    localparam integer AUTO_PLAY_CYCLES = (CLK_FREQ_HZ / 1000) * AUTO_PLAY_MS;

    reg [31:0] auto_count;
    reg        next_pending;
    reg        prev_pending;

    initial begin
        if (CLK_FREQ_HZ < 1000 || AUTO_PLAY_MS < 1 || AUTO_PLAY_CYCLES < 1) begin
            $display("SLIDESHOW_POLICY_CONFIG_ERROR invalid timing parameter");
            $finish;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step_next   <= 1'b0;
            step_prev   <= 1'b0;
            auto_play_en <= 1'b0;
            auto_count  <= 32'd0;
            next_pending <= 1'b0;
            prev_pending <= 1'b0;
        end else begin
            step_next <= 1'b0;
            step_prev <= 1'b0;

            if (!scan_ready || image_count == 3'd0) begin
                auto_play_en <= 1'b0;
                auto_count   <= 32'd0;
                next_pending <= 1'b0;
                prev_pending <= 1'b0;
            end else begin
                if (next_event)
                    next_pending <= 1'b1;
                if (prev_event)
                    prev_pending <= 1'b1;

                if (image_count <= 3'd1) begin
                    auto_play_en <= 1'b0;
                    auto_count   <= 32'd0;
                end else if (auto_toggle_event) begin
                    auto_play_en <= ~auto_play_en;
                    auto_count   <= 32'd0;
                end else if (auto_play_en && display_valid && !load_busy) begin
                    if (auto_count >= AUTO_PLAY_CYCLES - 1) begin
                        auto_count   <= 32'd0;
                        next_pending <= 1'b1;
                    end else begin
                        auto_count <= auto_count + 1'b1;
                    end
                end else begin
                    auto_count <= 32'd0;
                end

                // Manual/queued next has priority over previous.
                if (display_valid && !load_busy && loader_ready) begin
                    if (next_pending) begin
                        step_next   <= 1'b1;
                        next_pending <= 1'b0;
                    end else if (prev_pending) begin
                        step_prev   <= 1'b1;
                        prev_pending <= 1'b0;
                    end
                end
            end
        end
    end
endmodule
