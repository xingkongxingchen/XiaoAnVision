`timescale 1ns/1ps
// Final gain covers normal music, emergency music and cue, before HDMI/tap.
// Gain moves one LSB per sample tick (~5.3ms full travel), no instantaneous wrap.
module pcm_master_volume(input wire clk,rst_n,sample_tick,
 input wire[7:0] volume,
 input wire in_valid,output wire in_ready,
 input wire signed[15:0] in_left,in_right,
 output reg out_valid,input wire out_ready,
 output reg signed[15:0] out_left,out_right);
 reg[7:0] gain;
 wire signed[24:0] scaled_left=in_left*$signed({1'b0,gain});
 wire signed[24:0] scaled_right=in_right*$signed({1'b0,gain});
 assign in_ready=!out_valid || out_ready;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin gain<=255;out_valid<=0;out_left<=0;out_right<=0;end
  else begin
   if(sample_tick)begin
    if(gain<volume)gain<=gain+1'b1;
    else if(gain>volume)gain<=gain-1'b1;
   end
   if(in_ready)begin
    out_valid<=in_valid;
    if(in_valid)begin
     out_left<=gain==255 ? in_left : scaled_left >>> 8;
     out_right<=gain==255 ? in_right : scaled_right >>> 8;
    end
   end
  end
 end
endmodule
