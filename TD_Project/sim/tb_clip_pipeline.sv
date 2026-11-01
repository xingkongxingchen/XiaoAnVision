`timescale 1ns/1ps
// Real shared frame reader, vendor async FIFO, pixel expansion and scene control.
// A latency/refresh memory responder enforces complete contiguous 128-word bursts.
module tb_clip_pipeline;
 reg cc=0,mc=0,pc=0,rst=0,sw=0,emergency=0;
 always #5 cc=~cc;always #5 mc=~mc;always #20 pc=~pc;
 wire rd,valid,fs,de,vs,hs,clip,under,scene;wire[20:0]addr;wire[31:0]data;
 wire[23:0]rgb;wire[9:0]vx;wire[7:0]error;wire[1:0]index;
 wire[3:0]checked;wire fault;
 media_video_pipeline #(.ENABLE_CLIP(1),.ENABLE_EMERGENCY(1),.ENABLE_CRC_DIAG(1),.ENABLE_THUMBNAILS(1),.ENABLE_PICTURE_ADJUST(1)) dut(
  .ctrl_clk(cc),.ctrl_rst_n(rst),.next_event(1'b0),.prev_event(1'b0),.toggle_auto_event(1'b0),
  .thumbnail_toggle_event(1'b0),.thumbnail_active(),.controls_busy(),
  .period_cfg_valid(1'b0),.period_cfg_cycles(32'd0),.auto_cfg_valid(1'b0),.auto_cfg_enabled(1'b0),
  .image_complete(4'hf),.player_enable(rst),.clip_switch(sw),.clip_ready(rst),.clip_active(clip),
  .emergency_requested(emergency),.emergency_scene_active(scene),.emergency_missing(),.scene_block_controls(),
  .mem_clk(mc),.mem_rst_n(rst),.controller_init_done(rst),.controller_busy(1'b0),.refresh_active(1'b0),
  .app_rd_en(rd),.app_rd_addr(addr),.sdram_rd_valid(valid),.sdram_rd_data(data),
  .brightness(8'hff),.picture_brightness(8'hff),.picture_contrast(8'h80),
  .pix_clk(pc),.pix_rst_n(rst),.video_clk(),.video_hs(hs),.video_vs(vs),.video_de(de),.video_de_lookahead(),.video_rgb(rgb),.video_x(vx),
  .active_index(index),.pending_index(),.auto_enabled(),.frame_start(fs),.reader_busy(),.reader_underflow(under),.video_error(error),
  .video_fade_alpha(),.video_fade_active(),.diag_checked(checked),.diag_fault(fault),.diag_index(),.diag_actual(),.diag_expected());
 defparam dut.u_reader.MAX_INFLIGHT_BURSTS=1;
 defparam dut.g_clip.u_clip_control.DEBOUNCE_FRAMES=0;
 // Accelerate dwell only; geometry, all twenty frame addresses and bus clocks are real.
 defparam dut.g_clip.u_clip_control.FRAME_CYCLES=500000;
 // Dwell/frame-count control has a separate complete 20-frame regression.
 // Keep full-raster integration focused on entry, two advances, exit and takeover.
 defparam dut.g_clip.u_clip_control.FRAMES=3;
 defparam dut.g_crc.u_probe.EXPECT0=32'h0000ba73;
 defparam dut.g_crc.u_probe.EXPECT1=32'h0000aeae;
 defparam dut.g_crc.u_probe.EXPECT2=32'h0000c88a;
 defparam dut.g_crc.u_probe.EXPECT3=32'h0000aba8;
 reg[31:0]clip_words[0:383999];
 function[23:0]color(input integer b,x,y);color={8'(b*53+x),8'(y),8'(x^y^(b*37))};endfunction
 reg[20:0]q[0:1023];integer wp=0,rp=0,cy=0,burst=0,lastaddr=0;
 reg last_rd=0,bvalid=0;reg[31:0]bdata=0;
 assign valid=bvalid;assign data=bdata;
 always @(posedge mc)begin
  cy++;bvalid<=0;
  if(rd)begin
   if(addr>=1612800)$fatal(1,"out-of-bounds address %h",addr);
   if(burst!=0 && addr!=lastaddr+1)$fatal(1,"split contiguous burst");
   q[wp%1024]=addr;wp++;burst++;lastaddr=addr;
   if(wp-rp>1023)$fatal(1,"queue overflow");
  end
  if(last_rd && !rd)begin if(burst!=128)$fatal(1,"burst length %0d",burst);burst=0;end
  last_rd=rd;
  if(rst && rp<wp && cy%2==0 && cy%1000>=40)begin:response
   integer a,off;
   a=q[rp%1024];rp++;bvalid<=1;
   if(a>=1228800)bdata<=clip_words[a-1228800];
   else begin off=a%307200;bdata<={8'd0,color(a/307200,off%640,off/640)};end
  end
 end
 integer loops=0;
 always @(posedge pc)if(dut.clip_restart)loops++;
 integer pixels=0,frames=0,clip_frames=0,normal_frames=0,alarm_frames=0;
 reg prevvs=1;reg[19:0]seen=0;
 always @(posedge pc)if(rst)begin:scoreboard
  integer x,y,f;reg[23:0]expect_rgb;
  if(error || under || fault)$fatal(1,"pipeline fault e=%h under=%b CRC=%b frames%0d",error,under,fault,frames);
  if(prevvs && !vs)begin
   if(pixels!=0)begin
    if(pixels!=307200)$fatal(1,"short raster %0d",pixels);
    frames++;
    $display("RASTER_PASS frame=%0d clip=%0b index=%0d",frames,clip,dut.clip_frame_index);
   end
   pixels=0;
  end
  prevvs<=vs;
  if(de)begin
   x=pixels%640;y=pixels/640;f=dut.clip_frame_index;
   if(vx!=x)$fatal(1,"x alignment");
   if(clip)expect_rgb=clip_words[f*19200+(y/4)*160+x/4][23:0];
   else expect_rgb=color(index,x,y);
   if(rgb!==expect_rgb)$fatal(1,"pixel clip%b frame%0d x%0d y%0d actual%h expected%h",clip,f,x,y,rgb,expect_rgb);
   if(pixels==0)begin
    if(clip)begin clip_frames++;seen[f]=1;end
    else if(scene)alarm_frames++;else normal_frames++;
   end
   pixels++;
  end
 end
 initial begin
  $readmemh("clip_words.hex",clip_words);
  #100;rst=1;wait(normal_frames>=1);wait(de);repeat(77)@(negedge pc);sw=1;
  wait(clip);wait(loops==2);wait(de);repeat(77)@(negedge pc);
  if(!clip)$fatal(1,"clip dropped between loops");
  sw=0;wait(!clip);wait(normal_frames>=2);
  if(seen!=20'h00007)$fatal(1,"frame coverage %h",seen);
  repeat(2)@(negedge vs);if(clip)$fatal(1,"low switch restarted");
  sw=0;repeat(20)@(negedge pc);sw=1;wait(clip);wait(de);repeat(88)@(negedge pc);emergency=1;
  wait(scene && !clip);wait(alarm_frames>=1);repeat(1)@(negedge vs);emergency=0;
  wait(!scene);repeat(2)@(negedge vs);
  if(error || under || fault || !checked[0] || !checked[3])$fatal(1,"restoration/CRC");
  $display("TB_PASS clip pipeline: two continuous loops of first 3 actual asset frames, %0d full output rasters, per-pixel scale checks; normal/alarm restoration, CRC, FIFO and 128-word bursts",frames);$finish;
 end
 initial begin #1800000000;$fatal(1,"timeout frame%0d",frames);end
endmodule
