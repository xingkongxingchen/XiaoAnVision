`timescale 1ns/1ps
module tb_clip_voice;
 reg clk=0,rst=0,active=0,ready=1,restart=0;always #5 clk=~clk;
 integer cycle=0,received=0;reg[7:0]reference[0:16383];
 reg we=0;reg[13:0]wa=0;reg[7:0]wd=0;
 wire tick;wire valid;wire signed[15:0]pcm;
 assign tick=cycle%12==0;
 clip_voice_player dut(
  .write_clk(clk),.write_en(we),.write_addr(wa),.write_data(wd),
  .clk(clk),.rst_n(rst),.active(active),.restart(restart),.sample_tick(tick),.sample_ready(ready),
  .sample_valid(valid),.sample_out(pcm));
 always @(posedge clk)cycle<=cycle+1;
 always @(posedge clk)if(rst && active && valid && ready)begin
  if(pcm!=={reference[received/6],8'd0})$fatal(1,"voice sample%0d actual%h",received,pcm);
  received++;
 end
 initial begin
  $readmemh("../assets/clip_voice.hex",reference);
  for(integer i=0;i<16000;i++)begin
   @(negedge clk);we=1;wa=i;wd=reference[i];
  end
  @(negedge clk);we=0;
  repeat(4)@(negedge clk);rst=1;repeat(4)@(negedge clk);active=1;
  wait(received==96000);@(negedge clk);restart=1;
  @(negedge clk);restart=0;received=0;
  wait(received==96000);@(negedge clk);active=0;
  repeat(10)@(negedge clk);received=0;active=1;
  repeat(1000)begin
   @(negedge clk);ready=cycle%19>4;
  end
  active=0;repeat(5)@(negedge clk);
  if(valid)$fatal(1,"voice did not cancel");
  $display("TB_PASS preloaded voice RAM: two continuous-active voice cycles, 192000 PCM outputs match 16000 signed bytes x6; loop restart, backpressure and cancel");$finish;
 end
 initial begin #25000000;$fatal(1,"timeout");end
endmodule
