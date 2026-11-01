`timescale 1ns/1ps
// MiCu sector_* -> existing sd_card_top. Preserve held request protocol.
// Add bounded wait and exact 512-byte checking instead of hardwired error=0.
module sd_sector_adapter #(parameter integer TIMEOUT_CYCLES=50000000)(
 input wire clk,rst,enable,
 input wire sector_req,input wire[31:0]sector_lba,
 output wire sector_busy,sector_valid,output wire[7:0]sector_byte,
 output wire[8:0]sector_byte_index,
 output reg sector_done,output reg[7:0]sector_error,
 output reg sd_sec_read,output reg[31:0]sd_sec_read_addr,
 input wire sd_sec_read_data_valid,input wire[7:0]sd_sec_read_data,
 input wire sd_sec_read_end
);
 reg busy;
 // Cycle-equivalent registered form of busy && count<512. It separates
 // the byte-valid fanout from the request/timeout busy control cone.
 reg emit_ready;
 reg[9:0]count;
 // Busy exits at TIMEOUT_CYCLES-1, so higher bits are unreachable. Keep the
 // held-request protocol and every observable cycle identical to the baseline.
 localparam integer TIMER_WIDTH=TIMEOUT_CYCLES<2 ? 1 : $clog2(TIMEOUT_CYCLES);
 reg[TIMER_WIDTH-1:0]timer;
 reg[2:0]guard;
 assign sector_busy=busy || guard!=0 || !enable;
 assign sector_valid=emit_ready && sd_sec_read_data_valid;
 assign sector_byte=sd_sec_read_data;
 assign sector_byte_index=count[8:0];
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   busy<=0;emit_ready<=0;count<=0;timer<=0;guard<=0;
   sector_done<=0;sector_error<=0;sd_sec_read<=0;sd_sec_read_addr<=0;
  end else begin
   sector_done<=0;
   if(guard!=0)guard<=guard-1'b1;
   if(!busy && guard==0 && enable && sector_req)begin
    busy<=1;emit_ready<=1;count<=0;timer<=0;sector_error<=0;
    sd_sec_read<=1;sd_sec_read_addr<=sector_lba;
   end else if(busy)begin
    if(sd_sec_read_data_valid && count<1023)count<=count+1'b1;
    if(sd_sec_read_data_valid && count==511)emit_ready<=0;
    if(sd_sec_read_end)begin
     busy<=0;emit_ready<=0;sd_sec_read<=0;sector_done<=1;guard<=4;
     sector_error<=((count+(sd_sec_read_data_valid ? 1 : 0))==512) ? 0 : 8'h02;
    end else if(timer>=TIMEOUT_CYCLES-1)begin
     busy<=0;emit_ready<=0;sd_sec_read<=0;sector_done<=1;sector_error<=8'h01;guard<=4;
    end else timer<=timer+1'b1;
   end
  end
 end
endmodule
