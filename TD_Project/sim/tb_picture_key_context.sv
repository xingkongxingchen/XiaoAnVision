`timescale 1ns/1ps
module tb_picture_key_context;
 reg clk=0,pc=0,rst=0,enable=0,emergency=0,sw=0,k1=1,k2=1;
 reg select_event=0,step_event=0,remote_valid=0;reg[1:0]remote_id=0;reg[7:0]remote_value=128;
 always #5 clk=~clk;always #20 pc=~pc;
 wire sd_card_clk=clk,loader_rst_n=rst;
 wire normal_keys_enabled,setting_mode,next_event,auto_toggle_event,menu_event;
 `include "picture_context_stage.vh"
 period_setting_control #(.CLK_HZ(1000),.DEBOUNCE_MS(3)) periods(
  .clk(clk),.rst_n(rst),.enable(enable),.emergency(emergency),.switch_in(sw),.key_plus_n(k1),.key_minus_n(k2),
  .setting_mode(setting_mode),.normal_keys_enabled(normal_keys_enabled),.period_valid(),.period_cycles(),.period_seconds(),.period_bcd());
 slideshow_key_router #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(3),.LONG_PRESS_MS(16),.ENABLE_THUMBNAILS(1),.ENABLE_PICTURE_MENU(1)) keys(
  .clk(clk),.rst_n(rst && normal_keys_enabled),.key_next_n(k1),.key_mode_n(k2),
  .next_event(next_event),.auto_toggle_event(auto_toggle_event),.prev_event(),.thumbnail_toggle_event(),.picture_menu_event(menu_event));
 wire rm,cm;integer pcnt=0;always @(posedge pc)pcnt<=pcnt+1;
 wire fs=pcnt%61==0;
 picture_adjust_control #(.ENABLE_EMERGENCY(1),.ENABLE_K3(1),.ENABLE_REMOTE(1)) reference_control(
  .ctrl_clk(clk),.ctrl_rst_n(rst),.enable(enable),.short1(next_event && normal_keys_enabled),.short2(auto_toggle_event && normal_keys_enabled),
  .long1((menu_event && normal_keys_enabled)||(setting_mode && rm)),.cancel(emergency),.k3_select(select_event),.k3_step(step_event),
  .remote_valid(remote_valid),.remote_id(remote_id),.remote_value(remote_value),.menu_mode(rm),
  .pix_clk(pc),.pix_rst_n(rst),.frame_start(fs),.brightness_pix(),.contrast_pix(),.menu_pix(),.volume_pix(),.selected_pix());
 picture_adjust_control #(.ENABLE_EMERGENCY(1),.ENABLE_K3(1),.ENABLE_REMOTE(1)) candidate_control(
  .ctrl_clk(clk),.ctrl_rst_n(rst),.enable(enable),.short1(next_event && picture_key_context),.short2(auto_toggle_event && picture_key_context),
  .long1((menu_event && normal_keys_enabled)||(setting_mode && cm)),.cancel(emergency),.k3_select(select_event),.k3_step(step_event),
  .remote_valid(remote_valid),.remote_id(remote_id),.remote_value(remote_value),.menu_mode(cm),
  .pix_clk(pc),.pix_rst_n(rst),.frame_start(fs),.brightness_pix(),.contrast_pix(),.menu_pix(),.volume_pix(),.selected_pix());
 integer checks=0,qualified=0;
 always @(posedge clk)if(rst)begin
  if(((next_event && normal_keys_enabled)!==(next_event && picture_key_context)) ||
     ((auto_toggle_event && normal_keys_enabled)!==(auto_toggle_event && picture_key_context)))$fatal(1,"eligibility changed an actual release event");
  if(next_event && normal_keys_enabled || auto_toggle_event && normal_keys_enabled)qualified++;
 end
 always @(negedge clk)if(rst)begin
  if({reference_control.brightness,reference_control.contrast,reference_control.volume,reference_control.selected,rm,
      reference_control.mailbox,reference_control.request} !==
     {candidate_control.brightness,candidate_control.contrast,candidate_control.volume,candidate_control.selected,cm,
      candidate_control.mailbox,candidate_control.request})$fatal(1,"picture control/reference mismatch");
  checks++;
 end
 initial begin
  repeat(5)@(negedge clk);rst=1;enable=1;
  for(integer i=0;i<20000;i++)begin
   @(negedge clk);
   if(i%40==0)k1=0;if(i%40==9)k1=1;
   if(i%53==0)k2=0;if(i%53==9)k2=1;
   if(i%613==0)sw=!sw;
   if(i%157==0)emergency=!emergency;
   enable=i%997<970;
   select_event=i%13==0;step_event=i%17==0;
   remote_valid=i%67==0;remote_id=i%3;remote_value=128+i%128;
  end
  @(negedge clk);k1=1;k2=1;sw=0;emergency=0;enable=1;select_event=0;step_event=0;remote_valid=0;
  repeat(50)@(negedge clk);
  if(checks<20000 || qualified<10)$fatal(1,"insufficient real key coverage %0d",qualified);
  $display("TB_PASS picture key context: %0d exact cycles, %0d actual release events; mode/emergency/enable changes, remote priority, K3 and mailbox identical",checks,qualified);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
