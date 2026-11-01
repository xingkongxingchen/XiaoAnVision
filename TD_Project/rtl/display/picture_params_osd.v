`timescale 1ns/1ps
// Always-visible decimal B/C values and 128-pixel bars, outside the old OSD.
// White = playback; yellow = adjustment menu. Parameters are frame-committed.
module picture_params_osd(
 input wire in_de,input wire[23:0]rgb_in,
 input wire[9:0]pixel_x,input wire[11:0]pixel_y,
 input wire[7:0]brightness,contrast,input wire menu_mode,
 output reg[23:0]rgb_out
);
 function[14:0]glyph;
  input[3:0]v;
  begin case(v)
   0:glyph=15'b111_101_101_101_111;
   1:glyph=15'b010_110_010_010_111;
   2:glyph=15'b111_001_111_100_111;
   3:glyph=15'b111_001_111_001_111;
   4:glyph=15'b101_101_111_001_001;
   5:glyph=15'b111_100_111_001_111;
   6:glyph=15'b111_100_111_101_111;
   7:glyph=15'b111_001_001_001_001;
   8:glyph=15'b111_101_111_101_111;
   9:glyph=15'b111_101_111_001_111;
   10:glyph=15'b110_101_110_101_110; // B
   11:glyph=15'b111_100_100_100_111; // C
   default:glyph=15'b000_010_000_010_000; // colon
  endcase end
 endfunction
 // Only the five documented menu levels are produced; no divider hardware.
 function[11:0]decimal;
  input[7:0]v;
  begin case(v)
   0:decimal=12'h000;64:decimal=12'h064;128:decimal=12'h128;
   192:decimal=12'h192;default:decimal=12'h255;
  endcase end
 endfunction
 reg[7:0]value;
 reg[11:0]digits;
 reg[3:0]character;
 reg[14:0]bits;
 integer dx,dy,row,col;
 reg hit,region;
 always @* begin
  rgb_out=rgb_in;value=brightness;digits=0;character=0;bits=0;
  dx=0;dy=0;row=0;col=0;hit=0;region=0;
  if(in_de && pixel_x>=416 && pixel_x<630 && pixel_y>=8 && pixel_y<48)begin
   dx=pixel_x-416;dy=pixel_y-8;
   value=(dy<20) ? brightness : contrast;
   digits=decimal(value);
   if(dy>=20)dy=dy-20;
   region=dy<14;
   // Five 8x10 character cells, each font dot enlarged 2x2.
   if(dx<40 && dy<10)begin
    case(dx/8)
     0:character=(pixel_y<28) ? 10 : 11;
     1:character=12;
     2:character=digits[11:8];
     3:character=digits[7:4];
     default:character=digits[3:0];
    endcase
    bits=glyph(character);row=dy/2;col=(dx%8)/2;
    if(col<3)hit=bits[14-row*3-col];
   end
   if(dx>=48 && dx<178 && dy>=2 && dy<12)begin
    if(dx==48 || dx==177 || dy==2 || dy==11)hit=1;
    else if(dx-49 < ({1'b0,value}+9'd1)/2)hit=1;
   end
   if(region)rgb_out=hit ? 24'hff0000 : 24'h101010;
  end
 end
endmodule
