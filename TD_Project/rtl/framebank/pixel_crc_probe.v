`timescale 1ns/1ps
// Passive CRC-16/CCITT-FALSE probe. RGB byte order; no data-path backpressure.
// SERIAL requires >= 3 clocks between input pixels (loader uses 64).
module pixel_crc_probe #(
 parameter integer IMAGE_WORDS=307200, SERIAL=0,
 parameter [31:0] EXPECT0=0, EXPECT1=0, EXPECT2=0, EXPECT3=0
)(
 input wire clk,rst_n,start,input wire[1:0]image_index,
 input wire data_valid,input wire[23:0]pixel_rgb,
 output reg[3:0]checked,bad,output reg fault,protocol_fault,
 output wire[1:0]fault_index,output wire[31:0]fault_actual,fault_expected
);
 localparam CW=IMAGE_WORDS<=2 ? 1 : $clog2(IMAGE_WORDS);
 reg[CW-1:0]count;
 reg active,last_word,done;
 reg[1:0]phase,index_q,result_index;
 reg[15:0]pending;
 reg[15:0]crc,result;
 function [15:0] crc_byte;
  input[15:0]c;input[7:0]b;reg[15:0]v;integer k;
  begin v=c^{b,8'd0};for(k=0;k<8;k=k+1)v=v[15] ? (v<<1)^16'h1021 : v<<1;crc_byte=v;end
 endfunction
 wire[15:0]after_r=crc_byte(crc,pixel_rgb[23:16]);
 wire[15:0]after_rgb=crc_byte(crc_byte(after_r,pixel_rgb[15:8]),pixel_rgb[7:0]);
 wire[7:0]serial_byte=phase==1 ? pending[15:8] : phase==2 ? pending[7:0] : pixel_rgb[23:16];
 wire[15:0]serial_next=crc_byte(crc,serial_byte);
 reg[31:0]expected;
 always @* case(result_index)
  0:expected=EXPECT0;1:expected=EXPECT1;2:expected=EXPECT2;default:expected=EXPECT3;
 endcase
 // Once the first mismatch is recorded, stop only the passive probe. Its
 // result registers are then the frozen capture; no duplicate capture bank.
 assign fault_index=result_index;
 assign fault_actual=result;
 assign fault_expected=expected;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   count<=0;active<=0;last_word<=0;done<=0;phase<=0;index_q<=0;
   result_index<=0;pending<=0;crc<=16'hffff;result<=0;protocol_fault<=0;
  end else begin
   done<=0;
   if(!fault && start)begin count<=0;active<=1;phase<=0;crc<=16'hffff;end
   else if(!fault && active)begin
    if(SERIAL && phase!=0 && data_valid)protocol_fault<=1;
    if(phase==0 && data_valid)begin
     if(count==0)index_q<=image_index;
     if(SERIAL)begin
      crc<=serial_next;pending<=pixel_rgb[15:0];phase<=1;last_word<=count==IMAGE_WORDS-1;
     end else begin
      crc<=after_rgb;
      if(count==IMAGE_WORDS-1)begin
       active<=0;done<=1;result<=after_rgb;
       result_index<=IMAGE_WORDS==1 ? image_index : index_q;
      end
     end
     if(count!=IMAGE_WORDS-1)count<=count+1'b1;
    end else if(SERIAL && phase==1)begin crc<=serial_next;phase<=2;end
    else if(SERIAL && phase==2)begin
     crc<=serial_next;phase<=0;
     if(last_word)begin active<=0;done<=1;result<=serial_next;result_index<=index_q;end
    end
   end
  end
 end
 // Separate result register keeps comparison out of the CRC feedback path.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin checked<=0;bad<=0;fault<=0;end
  else if(done)begin
   checked[result_index]<=1;
   if(result!=expected)begin
    bad[result_index]<=1;
    fault<=1;
   end
  end
 end
endmodule
