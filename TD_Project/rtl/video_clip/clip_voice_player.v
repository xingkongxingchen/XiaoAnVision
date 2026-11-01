`timescale 1ns/1ps
// Preloaded 8-kHz signed PCM RAM. Six 48-kHz samples per stored byte.
// Write only during boot; ready handoff precedes playback in the pixel domain.
module clip_voice_player #(
 parameter integer SAMPLES=16000
)(
 input wire write_clk,write_en,input wire[13:0]write_addr,input wire[7:0]write_data,
 input wire clk,rst_n,active,restart,sample_tick,sample_ready,
 output reg sample_valid,output reg signed[15:0]sample_out
);
 reg[7:0]voice_ram[0:16383]; /* fehdl force_ram=1, ram_style="bram" */
 reg[7:0]rom_value;reg[13:0]address;reg[2:0]repeat_count;
 reg exhausted,warming;
 always @(posedge write_clk)if(write_en)voice_ram[write_addr]<=write_data;
 always @(posedge clk)rom_value<=voice_ram[address];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin address<=0;repeat_count<=0;exhausted<=0;sample_valid<=0;sample_out<=0;warming<=1;end
  else if(!active || restart)begin address<=0;repeat_count<=0;exhausted<=0;sample_valid<=0;sample_out<=0;warming<=1;end
  // The synchronous RAM still holds the previous address on the reset edge.
  // Wait one cycle so every restart phase begins with byte zero.
  else if(warming)begin warming<=0;sample_valid<=0;end
  else begin
   if(sample_valid && sample_ready)sample_valid<=0;
   if(sample_tick && (!sample_valid || sample_ready))begin
    sample_valid<=1;sample_out<=exhausted ? 16'd0 : {rom_value,8'd0};
    if(!exhausted)begin
     if(repeat_count==5)begin
      repeat_count<=0;
      if(address==SAMPLES-1)exhausted<=1;else address<=address+1'b1;
     end else repeat_count<=repeat_count+1'b1;
    end
   end
  end
 end
endmodule
