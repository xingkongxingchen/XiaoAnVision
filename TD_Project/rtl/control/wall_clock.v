`timescale 1ns/1ps
// Same pixel-clock domain as UART and OSD; no asynchronous multi-bit time bus.
module wall_clock #(parameter integer SECOND_CYCLES=25000000)(
 input wire clk,rst_n,set_valid,
 input wire[23:0]set_bcd,
 output reg valid,
 output reg[23:0]bcd
);
 localparam integer CW=SECOND_CYCLES>1 ? $clog2(SECOND_CYCLES) : 1;
 reg[CW-1:0]count;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin valid<=0;bcd<=0;count<=0;end
  else if(set_valid)begin valid<=1;bcd<=set_bcd;count<=0;end
  else if(!valid)count<=0;
  else if(count==SECOND_CYCLES-1)begin
   count<=0;
   if(bcd[3:0]!=9)bcd[3:0]<=bcd[3:0]+1'b1;
   else begin
    bcd[3:0]<=0;
    if(bcd[7:4]!=5)bcd[7:4]<=bcd[7:4]+1'b1;
    else begin
     bcd[7:4]<=0;
     if(bcd[11:8]!=9)bcd[11:8]<=bcd[11:8]+1'b1;
     else begin
      bcd[11:8]<=0;
      if(bcd[15:12]!=5)bcd[15:12]<=bcd[15:12]+1'b1;
      else begin
       bcd[15:12]<=0;
       if(bcd[23:16]==8'h23)bcd[23:16]<=0;
       else if(bcd[19:16]!=9)bcd[19:16]<=bcd[19:16]+1'b1;
       else begin bcd[19:16]<=0;bcd[23:20]<=bcd[23:20]+1'b1;end
      end
     end
    end
   end
  end else count<=count+1'b1;
 end
endmodule
