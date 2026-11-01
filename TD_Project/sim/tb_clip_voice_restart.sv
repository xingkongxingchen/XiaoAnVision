`timescale 1ns/1ps
module tb_clip_voice_restart;
 reg clk=0,rst=0,active=0,restart=0,ready=0,we=0;
 reg[13:0]wa=0;reg[7:0]wd=0;
 always #5 clk=~clk;
 integer cycle=0,received=0,rounds=0;
 wire tick=cycle%3==0;wire valid;wire signed[15:0]pcm;
 clip_voice_player #(.SAMPLES(8)) dut(.write_clk(clk),.write_en(we),.write_addr(wa),.write_data(wd),
 .clk(clk),.rst_n(rst),.active(active),.restart(restart),.sample_tick(tick),.sample_ready(ready),.sample_valid(valid),.sample_out(pcm));
 always @(posedge clk)cycle<=cycle+1;
 always @(posedge clk)if(rst && active && valid && ready && !restart)begin
  if(pcm!=={8'(17+received/6),8'd0})$fatal(1,"restart phase round%0d sample%0d actual%h",rounds,received,pcm);
  received++;
 end
 initial begin
  for(integer i=0;i<8;i++)begin @(negedge clk);we=1;wa=i;wd=17+i;end
  @(negedge clk);we=0;rst=1;
  repeat(4)@(negedge clk);active=1;ready=1;
  for(integer j=0;j<6;j++)begin
   wait(received==48);@(negedge clk);ready=0;
   repeat(j+1)@(negedge clk);restart=1;
   @(negedge clk);restart=0;received=0;rounds++;ready=1;
  end
  wait(received==48);@(negedge clk);active=0;
  $display("TB_PASS voice loop restart across all sample-tick phases; seven ordered clips without lowering active");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
