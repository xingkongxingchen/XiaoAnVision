`timescale 1ns/1ps
module tb_period_cached #(parameter DIRECT=1,EMERGENCY=1,DEFAULT_PERIOD=5);
 reg sc=0,pc=0,rst=0;always #5 sc=~sc;always #7 pc=~pc;
 reg nx=0,pv=0,se=0,pa=0,re=0,tg=0,cv=0,av=0,ae=0;
 reg[1:0]si=0,ri=0;reg[3:0]images=15;reg[31:0]period=5;
 integer pixcy=0,checks=0;always @(posedge pc)pixcy<=pixcy+1;
 wire fs=pixcy%11==0;wire[46:0]d,q;
 media_player_control #(.DEFAULT_PERIOD_CYCLES(DEFAULT_PERIOD),.MIN_PERIOD_CYCLES(1),.MAX_PERIOD_CYCLES(128),.ENABLE_DIRECT_SELECT(DIRECT),.ENABLE_EMERGENCY(EMERGENCY)) dut(
 .sys_clk(sc),.sys_rst_n(rst),.next_event(nx),.prev_event(pv),.select_event(se),.select_index(si),.pause_auto(pa),.restore_event(re),.restore_index(ri),
 .toggle_auto_event(tg),.period_cfg_valid(cv),.period_cfg_cycles(period),.auto_cfg_valid(av),.auto_cfg_enabled(ae),.image_complete(images),
 .auto_enabled(d[46]),.active_period_cycles(d[45:14]),.pending_index(d[13:12]),.control_error(d[11:4]),.request_busy(d[3]),
 .pix_clk(pc),.pix_rst_n(rst),.frame_start(fs),.active_index(d[2:1]),.index_commit(d[0]));
 reference_player_control #(.DEFAULT_PERIOD_CYCLES(DEFAULT_PERIOD),.MIN_PERIOD_CYCLES(1),.MAX_PERIOD_CYCLES(128),.ENABLE_DIRECT_SELECT(DIRECT),.ENABLE_EMERGENCY(EMERGENCY)) refdut(
 .sys_clk(sc),.sys_rst_n(rst),.next_event(nx),.prev_event(pv),.select_event(se),.select_index(si),.pause_auto(pa),.restore_event(re),.restore_index(ri),
 .toggle_auto_event(tg),.period_cfg_valid(cv),.period_cfg_cycles(period),.auto_cfg_valid(av),.auto_cfg_enabled(ae),.image_complete(images),
 .auto_enabled(q[46]),.active_period_cycles(q[45:14]),.pending_index(q[13:12]),.control_error(q[11:4]),.request_busy(q[3]),
 .pix_clk(pc),.pix_rst_n(rst),.frame_start(fs),.active_index(q[2:1]),.index_commit(q[0]));
 always @(negedge sc)if(rst)begin
  if(d!==q || dut.auto_counter!==refdut.auto_counter)$fatal(1,"cycle mismatch check%0d d%h q%h counter%0d/%0d",checks,d,q,dut.auto_counter,refdut.auto_counter);
  if(dut.active_period_last!==d[45:14]-32'd1)$fatal(1,"cached threshold stale");checks++;
 end
 reg[31:0]random_word=32'hc819372a;
 task randomize_input;begin
  random_word=random_word^(random_word<<13);random_word=random_word^(random_word>>17);random_word=random_word^(random_word<<5);
  nx=random_word[4:0]==0;pv=random_word[9:5]==0;se=random_word[13:10]==0;re=random_word[17:14]==0;pa=random_word[20:18]==0;
  tg=random_word[25:21]==0;cv=random_word[29:26]==0;av=random_word[3:0]==1;ae=random_word[30];si=random_word[6:5];ri=random_word[8:7];images=random_word[12:9];
  case(random_word[16:13])
   0:period=0;1:period=1;2:period=128;3:period=129;4:period=32'hffffffff;default:period={25'd0,random_word[31:25]}+1;
  endcase
 end endtask
 initial begin
  repeat(8)@(negedge sc);#1;rst=1;
  av=1;ae=1;@(negedge sc);#1;av=0;
  repeat(250)@(negedge sc);
  for(integer i=0;i<50000;i++)begin @(negedge sc);#1;randomize_input();end
  rst=0;repeat(8)@(negedge sc);#1;rst=1;nx=0;pv=0;se=0;re=0;pa=0;tg=0;cv=0;av=0;
  repeat(100)@(negedge sc);
  $display("TB_PASS cached period threshold cycle-equivalent: DIRECT%0d EMERGENCY%0d DEFAULT%0d checks%0d; randomized valid/invalid periods, expiration, manual controls, mailbox, pause, emergency and reset",DIRECT,EMERGENCY,DEFAULT_PERIOD,checks);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
