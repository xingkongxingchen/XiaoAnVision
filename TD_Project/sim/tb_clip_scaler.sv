`timescale 1ns/1ps
module tb_clip_scaler;
 reg clk=0,rst=0,active=0;always #5 clk=~clk;
 integer hc=0,yc=0,consumed=0,pixels=0;
 wire de=hc>=32 && yc<480;
 wire[11:0]x=de ? hc-32 : 0;
 wire[11:0]y=yc;
 wire[11:0]nx=hc+1>=32 ? hc+1-32 : 0;
 wire consume,valid;wire[23:0]rgb;
 function[23:0]color(input integer x,y);color={8'(x),8'(y),8'(x^y)};endfunction
 wire[23:0]source=color(consumed%160,consumed/160);
 clip_nn_expand dut(.clk(clk),.rst_n(rst),.active(active),.de(de),.x(x),.y(y),.next_x(nx),
  .source_rgb(source),.source_valid(1'b1),.consume(consume),.rgb(rgb),.valid(valid));
 always @(posedge clk)if(rst && active)begin
  if(hc==671)begin hc<=0;yc<=yc+1;end else hc<=hc+1;
  if(consume)consumed<=consumed+1;
 end
 always @(negedge clk)if(rst && active && de)begin
  if(!valid || rgb!==color(x/4,y/4))$fatal(1,"scaler x%0d y%0d actual%h expected%h",x,y,rgb,color(x/4,y/4));
  pixels++;
 end
 initial begin
  repeat(4)@(negedge clk);rst=1;active=1;
  wait(yc==480);@(negedge clk);
  if(pixels!=307200 || consumed!=19200)$fatal(1,"counts %0d %0d",pixels,consumed);
  $display("TB_PASS 160x120 -> 640x480: all 307200 pixels, 19200 FIFO consumes, synchronous line RAM and fourfold repetition");$finish;
 end
 initial begin #4000000;$fatal(1,"timeout");end
endmodule
