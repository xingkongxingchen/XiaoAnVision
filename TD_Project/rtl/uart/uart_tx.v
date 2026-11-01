module uart_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy,
    output reg        done
);
    reg [3:0] phase;
    reg [7:0] data_latched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx           <= 1'b1;
            busy         <= 1'b0;
            done         <= 1'b0;
            phase        <= 4'd0;
            data_latched <= 8'd0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                tx <= 1'b1;
                if (start) begin
                    data_latched <= data;
                    busy         <= 1'b1;
                    phase        <= 4'd0;
                end
            end else if (tick) begin
                case (phase)
                    4'd0: begin
                        tx    <= 1'b0;
                        phase <= 4'd1;
                    end
                    4'd1, 4'd2, 4'd3, 4'd4,
                    4'd5, 4'd6, 4'd7, 4'd8: begin
                        tx    <= data_latched[phase-1'b1];
                        phase <= phase + 1'b1;
                    end
                    4'd9: begin
                        tx    <= 1'b1;
                        phase <= 4'd10;
                    end
                    default: begin
                        tx    <= 1'b1;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        phase <= 4'd0;
                    end
                endcase
            end
        end
    end
endmodule
