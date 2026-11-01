`timescale 1ns/1ps
// Independent bilingual banner; normal subtitle cannot hide it.
module emergency_scene_overlay(
 input wire clk,rst_n,vsync,de,active,missing,
 input wire[9:0]pixel_x,
 input wire[23:0]rgb_in,
 output reg[23:0]rgb_out
);
 reg[9:0]line_y;
 reg de_q;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin line_y<=0;de_q<=0;end
  else begin
   de_q<=de;
   if(!vsync)line_y<=0;else if(de_q && !de)line_y<=line_y+1'b1;
  end
 end
 // 5x7 bitmaps, row zero in bits 34:30. Scale 2x for a readable 16-pixel cell.
 function[34:0]glyph;
  input[7:0]c;
  begin case(c)
   "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
   "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
   "D":glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
   "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
   "G":glyph={5'b01110,5'b10001,5'b10000,5'b10111,5'b10001,5'b10001,5'b01110};
   "I":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b11111};
   "M":glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
   "N":glyph={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
   "O":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
   "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
   "Y":glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
   default:glyph=0;
  endcase end
 endfunction
 reg[7:0]character;
 reg[34:0]bits;
 wire[9:0]text_x=pixel_x-16;
 wire[9:0]text_y=line_y-16;
 localparam[143:0]MISSING_TEXT="NO EMERGENCY IMAGE";
 localparam[111:0]ACTIVE_TEXT="EMERGENCY DEMO";
 // Emergency demo / please remain calm. First character in low byte.
 localparam[79:0]SCENE_TEXT=80'h9e9d9c9b9a2099989796;
 localparam[79:0]NORMAL_TEXT=80'h00000000959493929190;
 wire[79:0]heading=active ? SCENE_TEXT : NORMAL_TEXT;
 wire[9:0]scene_x=pixel_x-(active ? 10'd320 : 10'd256);
 wire[7:0]scene_code=heading[scene_x[7:4]*8+:8];
 wire[15:0]scene_row;
 scene_chinese_font u_scene_font(.code(scene_code),.row(text_y[3:0]),.pixels(scene_row));
 always @*begin
  character=32;bits=0;rgb_out=rgb_in;
  if(active && de)begin
   if(pixel_x<4 || pixel_x>=636)rgb_out=24'hff3030;
   if(line_y<40)rgb_out=line_y>=38 ? 24'hff3030 : 24'h802020;
   if(pixel_x>=16 && pixel_x<304 && line_y>=16 && line_y<32)begin
    if(missing)character=MISSING_TEXT[(17-text_x[8:4])*8+:8];
    else if(text_x[8:4]<14)character=ACTIVE_TEXT[(13-text_x[8:4])*8+:8];
    bits=glyph(character);
    if(text_x[3:1]<5 && text_y[3:1]<7 && bits[34-text_y[3:1]*5-text_x[3:1]])rgb_out=24'hffffff;
   end
   if(pixel_x>=320 && pixel_x<480 && line_y>=16 && line_y<32 && scene_row[15-scene_x[3:0]])
    rgb_out=24'hffffff;
  end
  if(!active && de && pixel_x>=256 && pixel_x<352 && line_y>=16 && line_y<32 && scene_row[15-scene_x[3:0]])
   rgb_out=24'hff0000;
 end
endmodule
