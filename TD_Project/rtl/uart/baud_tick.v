module baud_tick #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200
)(
    input  wire clk,
    input  wire rst_n,
    output reg  tick
);
    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    reg [31:0] baud_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 32'd0;
            tick     <= 1'b0;
        end else if (baud_cnt == CLKS_PER_BIT - 1) begin
            baud_cnt <= 32'd0;
            tick     <= 1'b1;
        end else begin
            baud_cnt <= baud_cnt + 1'b1;
            tick     <= 1'b0;
        end
    end
endmodule
