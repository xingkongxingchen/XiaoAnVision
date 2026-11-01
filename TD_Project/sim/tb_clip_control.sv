`timescale 1ns/1ps
module tb_clip_control #(parameter FRAME_PERIOD=100);
 reg clk=0,rst=0,sw=0,ready=0,blocked=0,emergency=0;
 always #5 clk=~clk;
 integer cycle=0,starts=0,finishes=0,loops=0,last_loop=0;
 reg prev=0;wire active,restart;wire[4:0]index;wire[20:0]base;
 wire fs=cycle%FRAME_PERIOD==0;
 reg[19:0]seen=0;
 clip_play_control #(.FRAME_CYCLES(1000)) dut(
  .clk(clk),.rst_n(rst),.switch_in(sw),.ready(ready),.frame_start(fs),
  .blocked(blocked),.emergency(emergency),.active(active),.restart(restart),.frame_index(index),.frame_base(base));
 always @(posedge clk)cycle<=cycle+1;
 always @(negedge clk)if(rst)begin
  if((active!=prev || restart) && cycle%FRAME_PERIOD!=1)$fatal(1,"non-atomic switch cycle%0d",cycle);
  if(active && !prev)begin starts++;last_loop=cycle;seen=0;end
  if(!active && prev)finishes++;
  if(restart)begin
   if(!active || !prev || index!=0 || base!=1228800)$fatal(1,"loop gap/address");
   if(cycle-last_loop<20000 || cycle-last_loop>20000+FRAME_PERIOD || seen!=20'hfffff)$fatal(1,"loop duration/coverage %h",seen);
   loops++;last_loop=cycle;seen=0;
  end
  if(active)seen[index]=1;
  if(active && (index>=20 || base!=1228800+19200*index))$fatal(1,"frame addressing");
  prev=active;
 end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  ready=1;sw=1;repeat(FRAME_PERIOD*2)@(negedge clk);sw=0;
  repeat(FRAME_PERIOD*4)@(negedge clk);
  if(active || starts!=0)$fatal(1,"two-frame bounce accepted");
  ready=0;sw=1;repeat(FRAME_PERIOD*5)@(negedge clk);if(active)$fatal(1,"not-ready started");
  blocked=1;ready=1;repeat(FRAME_PERIOD*5)@(negedge clk);if(active)$fatal(1,"blocked started");
  blocked=0;wait(active);wait(loops==3);@(negedge clk);
  if(starts!=1 || finishes!=0)$fatal(1,"held-high continuity");
  sw=0;wait(!active);repeat(FRAME_PERIOD*5)@(negedge clk);
  if(starts!=1 || finishes!=1)$fatal(1,"low should stop");
  sw=1;wait(active);repeat(500)@(negedge clk);emergency=1;wait(!active);
  repeat(FRAME_PERIOD*4)@(negedge clk);if(active)$fatal(1,"emergency priority");
  emergency=0;wait(active);ready=0;wait(!active);
  repeat(FRAME_PERIOD*4)@(negedge clk);if(active)$fatal(1,"missing readiness");
  ready=1;wait(active);sw=0;wait(!active);
  ready=0;sw=1;repeat(FRAME_PERIOD*5)@(negedge clk);if(active)$fatal(1,"missing file started");
  rst=0;repeat(4)@(negedge clk);prev=0;rst=1;
  repeat(FRAME_PERIOD*5)@(negedge clk);if(active)$fatal(1,"reset/ready");
  $display("TB_PASS SW1 high: three gap-free 20-frame loops with frame-atomic addresses/duration and voice restart; low cancellation, debounce, deferred boot, blocked, emergency resume, readiness loss and reset");$finish;
 end
 initial begin #4000000;$fatal(1,"timeout");end
endmodule
