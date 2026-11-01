module uart_response_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       response_valid,
    input  wire [2:0] response_id,
    output wire       response_ready,
    input  wire       tx_busy,
    input  wire       tx_done,
    output reg        tx_start,
    output reg  [7:0] tx_data
);
    localparam [2:0] RESP_OK  = 3'd0;
    localparam [2:0] RESP_ERR = 3'd1;
    localparam [2:0] RESP_ON  = 3'd2;

    reg       active;
    reg [2:0] active_id;
    reg [2:0] byte_index;
    reg [2:0] byte_count;
    reg       waiting_done;

    assign response_ready = !active;

    function [7:0] response_byte;
        input [2:0] kind;
        input [2:0] index;
        begin
            case (kind)
                RESP_OK: begin
                    case (index)
                        3'd0: response_byte = "O";
                        3'd1: response_byte = "K";
                        3'd2: response_byte = 8'h0D;
                        default: response_byte = 8'h0A;
                    endcase
                end
                RESP_ERR: begin
                    case (index)
                        3'd0: response_byte = "E";
                        3'd1: response_byte = "R";
                        3'd2: response_byte = "R";
                        3'd3: response_byte = 8'h0D;
                        default: response_byte = 8'h0A;
                    endcase
                end
                RESP_ON: begin
                    case (index)
                        3'd0: response_byte = "O";
                        3'd1: response_byte = "N";
                        3'd2: response_byte = 8'h0D;
                        default: response_byte = 8'h0A;
                    endcase
                end
                default: begin
                    case (index)
                        3'd0: response_byte = "O";
                        3'd1: response_byte = "F";
                        3'd2: response_byte = "F";
                        3'd3: response_byte = 8'h0D;
                        default: response_byte = 8'h0A;
                    endcase
                end
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active     <= 1'b0;
            active_id  <= RESP_ERR;
            byte_index <= 3'd0;
            byte_count <= 3'd0;
            waiting_done <= 1'b0;
            tx_start   <= 1'b0;
            tx_data    <= 8'd0;
        end else begin
            tx_start <= 1'b0;

            if (response_valid && response_ready) begin
                active     <= 1'b1;
                active_id  <= response_id;
                byte_index <= 3'd0;
                waiting_done <= 1'b0;
                case (response_id)
                    RESP_OK, RESP_ON: byte_count <= 3'd4;
                    default:          byte_count <= 3'd5;
                endcase
            end

            if (active && !waiting_done && !tx_busy) begin
                tx_data  <= response_byte(active_id, byte_index);
                tx_start <= 1'b1;
                waiting_done <= 1'b1;
            end else if (active && waiting_done && tx_done) begin
                waiting_done <= 1'b0;
                if (byte_index == byte_count - 1'b1) begin
                    active     <= 1'b0;
                    byte_index <= 3'd0;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end
        end
    end
endmodule
