`timescale 1ns/1ps
// 160x120 -> 640x480 nearest neighbour. Fetch each source pixel once;
// a synchronous 160-word line RAM supplies the next three output rows.
module clip_nn_expand #(
 parameter integer WIDTH=160, HEIGHT=120
)(
 input wire clk,rst_n,active,de,input wire[11:0]x,y,next_x,
 input wire[23:0]source_rgb,input wire source_valid,
 output wire consume,output wire[23:0]rgb,output wire valid
);
 reg[23:0]line_ram[0:WIDTH-1]; /* fehdl force_ram=1, ram_style="bram" */
 reg[23:0]line_pixel;
 wire[7:0]column=x[9:2];
 wire[7:0]next_column=next_x[9:2];
 always @(posedge clk)begin
  if(active && de && y[1:0]==0 && x[1:0]==0 && source_valid && column<WIDTH)
   line_ram[column]<=source_rgb;
  line_pixel<=line_ram[next_column<WIDTH ? next_column : 8'd0];
 end
 assign consume=active && de && y[1:0]==0 && x[1:0]==3;
 assign rgb=y[1:0]==0 ? source_rgb : line_pixel;
 assign valid=active && (y[1:0]!=0 || source_valid);
endmodule
