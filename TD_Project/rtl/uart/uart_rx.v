module uart_rx #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer BAUD_RATE   = 115_200,
    parameter integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid,
    output reg        framing_error
);
    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_START = 2'd1;
    localparam [1:0] ST_DATA  = 2'd2;
    localparam [1:0] ST_STOP  = 2'd3;
    localparam integer HALF_BIT = (CLKS_PER_BIT - 1) / 2;

    reg rx_meta;
    reg rx_sync;
    reg [1:0] state;
    reg [31:0] sample_cnt;
    reg [2:0] bit_idx;
    reg [7:0] data_shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            sample_cnt <= 32'd0;
            bit_idx    <= 3'd0;
            data_shift <= 8'd0;
            data       <= 8'd0;
            valid      <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            valid <= 1'b0;
            framing_error <= 1'b0;
            case (state)
                ST_IDLE: begin
                    sample_cnt <= 32'd0;
                    bit_idx    <= 3'd0;
                    if (!rx_sync)
                        state <= ST_START;
                end

                ST_START: begin
                    if (sample_cnt == HALF_BIT) begin
                        sample_cnt <= 32'd0;
                        if (!rx_sync)
                            state <= ST_DATA;
                        else
                            state <= ST_IDLE;
                    end else begin
                        sample_cnt <= sample_cnt + 1'b1;
                    end
                end

                ST_DATA: begin
                    if (sample_cnt == CLKS_PER_BIT - 1) begin
                        sample_cnt         <= 32'd0;
                        data_shift[bit_idx] <= rx_sync;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        sample_cnt <= sample_cnt + 1'b1;
                    end
                end

                ST_STOP: begin
                    if (sample_cnt == CLKS_PER_BIT - 1) begin
                        sample_cnt <= 32'd0;
                        state      <= ST_IDLE;
                        if (rx_sync) begin
                            data  <= data_shift;
                            valid <= 1'b1;
                        end else begin
                            framing_error <= 1'b1;
                        end
                    end else begin
                        sample_cnt <= sample_cnt + 1'b1;
                    end
                end

                default: begin
                    state      <= ST_IDLE;
                    sample_cnt <= 32'd0;
                    bit_idx    <= 3'd0;
                end
            endcase
        end
    end
endmodule
