`timescale 1ns/1ps
// Normalize the existing 640x480 timing to active x=0..639, blank x=640..799.
// Falling HS is 16 clocks into horizontal blank. No video pipeline is changed.
module hdmi_video_position (
    input wire clk,
    input wire rst_n,
    input wire hsync,
    output wire [9:0] video_x
);
    reg previous_hsync;
    reg [9:0] next_x;
    wire falling_hsync = previous_hsync && !hsync;
    assign video_x = falling_hsync ? 10'd656 : next_x;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            previous_hsync <= 1'b1;
            next_x <= 10'd640;
        end else begin
            previous_hsync <= hsync;
            if (falling_hsync)
                next_x <= 10'd657;
            else if (next_x == 10'd799)
                next_x <= 10'd0;
            else
                next_x <= next_x + 1'b1;
        end
    end
endmodule
