`timescale 1ns/1ps
// Fixed first-stall record. Held-bus request/ack snapshot across SD/memory
// clocks. Does not issue resets, retries, writes, or alter normal loading.
module load_progress_probe #(
    parameter integer STALL_CYCLES = 20_000_000
)(
    input wire sd_clk, mem_clk, rst,
    input wire load_busy, parser_idle, write_req, pixel_valid,
    input wire [3:0] load_status, // target index, parser done, memory done
    input wire [19:0] mem_pixels,
    input wire [8:0] fifo_level,
    input wire overflow, underflow,
    input wire load_failed,
    input wire [3:0] error_code,
    input wire [31:0] file_len,pixel_offset,
    output reg captured,
    output reg [31:0] page0, page1, page2
);
    localparam integer WAIT_BITS = STALL_CYCLES < 2 ? 1 : $clog2(STALL_CYCLES);
    reg [WAIT_BITS-1:0] wait_count;
    reg [19:0] source_pixels;
    reg requested;
    reg [2:0] request_sync,ack_sync;
    reg ack_mem;
    reg [29:0] mem_snapshot;
    always @(posedge mem_clk or posedge rst) begin
        if(rst) begin request_sync<=0;ack_mem<=0;mem_snapshot<=0;end
        else begin
            request_sync<={request_sync[1:0],requested};
            if(request_sync[2] && !ack_mem) begin
                mem_snapshot<={underflow,fifo_level,mem_pixels};
                ack_mem<=1'b1;
            end
        end
    end
    always @(posedge sd_clk or posedge rst) begin
        if(rst) begin
            wait_count<=0;source_pixels<=0;requested<=0;ack_sync<=0;
            captured<=0;page0<=0;page1<=0;page2<=0;
        end else begin
            ack_sync<={ack_sync[1:0],ack_mem};
            if(write_req) source_pixels<=0;
            else if(pixel_valid) source_pixels<=source_pixels+1'b1;
            if(!requested && !captured) begin
                // Same SD clock domain. Freeze the exhausted retry, not a
                // recoverable first rejection. F distinguishes header pages.
                if(load_failed) begin
                    page0<={4'he,({2'b00,load_status[3:2]}+4'd1),4'hf,error_code,16'd0};
                    page1<=file_len;
                    page2<=pixel_offset;
                    captured<=1'b1;
                end else if(load_busy && parser_idle) begin
                    if(wait_count==STALL_CYCLES-1) begin
                        requested<=1'b1;
                        page0<={4'he,({2'b00,load_status[3:2]}+4'd1),
                                load_status[1:0],overflow,1'b0,20'd0};
                        page1<={12'ha00,source_pixels};
                    end else wait_count<=wait_count+1'b1;
                end else wait_count<=0;
            end
            if(ack_sync[2] && !captured) begin
                page0[20]<=mem_snapshot[29];
                page0[8:0]<=mem_snapshot[28:20];
                page2<={12'hb00,mem_snapshot[19:0]};
                captured<=1'b1;
            end
        end
    end
endmodule
