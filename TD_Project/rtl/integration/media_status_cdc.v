`timescale 1ns/1ps
// Bundled-data mailbox: hold the whole {valid,id} bus until pixel-domain ACK.
// New changes while busy coalesce into the latest status after acknowledgement.
module media_status_cdc (
    input wire source_clk,
    input wire source_rst,
    input wire [2:0] source_status,
    input wire pixel_clk,
    input wire pixel_rst_n,
    output reg [2:0] pixel_status
);
    reg [2:0] mailbox;
    reg request_toggle;
    reg acknowledge_toggle;
    reg [1:0] ack_sync;
    reg [1:0] request_sync;
    always @(posedge source_clk or posedge source_rst) begin
        if (source_rst) begin
            mailbox <= 3'd0;
            request_toggle <= 1'b0;
            ack_sync <= 2'b00;
        end else begin
            ack_sync <= {ack_sync[0], acknowledge_toggle};
            if (ack_sync[1] == request_toggle && mailbox != source_status) begin
                mailbox <= source_status;
                request_toggle <= ~request_toggle;
            end
        end
    end
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            request_sync <= 2'b00;
            acknowledge_toggle <= 1'b0;
            pixel_status <= 3'd0;
        end else begin
            request_sync <= {request_sync[0], request_toggle};
            if (request_sync[1] != acknowledge_toggle) begin
                pixel_status <= mailbox;
                acknowledge_toggle <= request_sync[1];
            end
        end
    end
endmodule
