`timescale 1ns/1ps
// Actual timing, player, CDC, SDRAM request sequencer, vendor FIFO and RGB
// adapter. Memory model accepts contiguous 128-word transactions and returns
// one word per two clocks, with refresh pauses. No forced reader internals.
module tb_p43_pipeline #(parameter REAL_SDRAM=0, SMOKE_ONLY=0, DIAG=1, INJECT=0, QUICK=1, EMERGENCY_TEST=0);
 reg ctrlclk=0,memclk=0,pixclk=0,rst=0;
 always #5 ctrlclk=~ctrlclk;
 always #5 memclk=~memclk;
 always #20 pixclk=~pixclk;
 reg toggle=0,next_event=0;
 reg emergency_request=0;
 reg[3:0]complete_images=4'hf;
 wire emergency_active,emergency_missing;
 reg[7:0]brightness=255,contrast=128;
 wire mode,rd,de,vs,hs,fs,underflow;
 wire[20:0]addr;
 wire valid;wire[31:0]data;
 wire mem_ready,mem_busy,mem_refresh;
 wire[23:0]rgb;wire[9:0]vx;wire[1:0]index;
 wire[7:0]error;
 wire[3:0]crc_checked;wire crc_fault;wire[1:0]crc_index;wire[31:0]crc_actual,crc_expected;
 media_video_pipeline #(.ENABLE_THUMBNAILS(1),.ENABLE_PICTURE_ADJUST(1),.ENABLE_CRC_DIAG(DIAG),.ENABLE_EMERGENCY(EMERGENCY_TEST)) dut(
  .controls_busy(),.emergency_requested(emergency_request),.emergency_scene_active(emergency_active),.emergency_missing(emergency_missing),.scene_block_controls(),
  .diag_checked(crc_checked),.diag_fault(crc_fault),.diag_index(crc_index),.diag_actual(crc_actual),.diag_expected(crc_expected),
  .ctrl_clk(ctrlclk),.ctrl_rst_n(rst),.next_event(next_event),.prev_event(1'b0),
  .toggle_auto_event(1'b0),.thumbnail_toggle_event(toggle),.thumbnail_active(mode),
  .period_cfg_valid(1'b0),.period_cfg_cycles(32'd0),.auto_cfg_valid(1'b0),.auto_cfg_enabled(1'b0),
  .image_complete(complete_images),.player_enable(mem_ready),.mem_clk(memclk),.mem_rst_n(rst),
  .controller_init_done(mem_ready),.controller_busy(mem_busy),.refresh_active(mem_refresh),
  .app_rd_en(rd),.app_rd_addr(addr),.sdram_rd_valid(valid),.sdram_rd_data(data),
  .brightness(8'hff),.pix_clk(pixclk),.pix_rst_n(rst),.video_clk(),.video_hs(hs),.video_vs(vs),
  .picture_brightness(brightness),.picture_contrast(contrast),
  .video_de(de),.video_de_lookahead(),.video_rgb(rgb),.video_x(vx),.active_index(index),
  .pending_index(),.auto_enabled(),.frame_start(fs),.reader_busy(),.reader_underflow(underflow),
  .video_error(error),.video_fade_alpha(),.video_fade_active());
  // Override only test references, independently computed with host binascii.
  defparam dut.u_reader.MAX_INFLIGHT_BURSTS=1;
  defparam dut.g_crc.u_probe.EXPECT0=32'h0000ba73;
  defparam dut.g_crc.u_probe.EXPECT1=32'h0000aeae;
  defparam dut.g_crc.u_probe.EXPECT2=32'h0000c88a;
  defparam dut.g_crc.u_probe.EXPECT3=32'h0000aba8;
 function[23:0] color(input integer bank,x,y);
  color={8'(bank*53+x),8'(y),8'(x^y^(bank*37))} ^ ((INJECT && bank==0 && x==123 && y==17) ? 24'h000001 : 24'd0);
 endfunction
 function automatic[7:0] adjust_ref(input integer v);
  integer bright,p,t;
  begin
   bright=brightness==255?v:v*brightness/256;
   p=(bright-128)*contrast;t=(p<0?-((-p+127)/128):p/128)+128;
   adjust_ref=t<0?0:t>255?255:t;
  end
 endfunction
 function automatic[23:0]adjust_color(input[23:0]v);
  adjust_color={adjust_ref(v[23:16]),adjust_ref(v[15:8]),adjust_ref(v[7:0])};
 endfunction
 reg[20:0]queue[0:4095];integer wp=0,rp=0,cycles=0,burst=0,reads=0;
 integer maddr,bank,offset;reg last_rd=0;reg[20:0]last_addr;
 generate if (REAL_SDRAM) begin : g_real
  wire init_done;
  reg loaded=0,we=0;reg[20:0]wa=0;reg[31:0]wd=0;
  assign mem_ready=init_done && loaded;
  sdram controller(.Clk(memclk),.Clk_sft(~memclk),.Rst(!rst),
   .Sdr_init_done(init_done),.Sdr_init_ref_vld(mem_refresh),.Sdr_busy(mem_busy),
   .App_wr_en(we),.App_wr_addr(wa),.App_wr_dm(4'd0),.App_wr_din(wd),
   .App_rd_en(rd),.App_rd_addr(addr),.Sdr_rd_en(valid),.Sdr_rd_dout(data));
  sdram_pin_model memory(.clk(controller.SDRAM_CLK),
   .cmd({controller.SDR_RAS,controller.SDR_CAS,controller.SDR_WE}),
   .ba(controller.SDR_BA),.addr(controller.SDR_ADDR),.dq(controller.SDR_DQ));
  // Populate through the actual application interface, not a guessed mapping
  // from application addresses into the pin model's physical array.
  initial begin
   wait(init_done);repeat(100)@(negedge memclk);
   for(integer base=0;base<1228800;base+=128)begin
    wait(!mem_busy && !mem_refresh);@(negedge memclk);
    for(integer k=0;k<128;k++)begin
     we=1;wa=base+k;wd={8'd0,color(wa/307200,(wa%307200)%640,(wa%307200)/640)};
     @(negedge memclk);
    end
    we=0;repeat(300)@(negedge memclk);
   end
   repeat(1000)@(negedge memclk);loaded=1;
   $display("PHYSICAL_PRELOAD complete through App_wr port");
  end
  always @(posedge memclk)if(rd)reads++;
  always @(posedge memclk)if(valid && dut.u_reader.returned_count_mem<680 && dut.u_reader.returned_count_mem>=628)
   $display("PHYSICAL_RETURN n=%d data=%h",dut.u_reader.returned_count_mem,data);
 end else begin : g_behavioral
 reg bvalid=0;reg[31:0]bdata=0;
 assign valid=bvalid;assign data=bdata;
 assign mem_ready=rst;assign mem_busy=0;assign mem_refresh=0;
 always @(posedge memclk)begin
  cycles=cycles+1;bvalid<=0;
  if(rd)begin
   if(addr>=1228800)$fatal(1,"out of bank address %h",addr);
   if(burst!=0 && addr!=last_addr+1)$fatal(1,"non-contiguous read burst");
   queue[wp%4096]=addr;wp++;burst++;reads++;
   if(wp-rp>4095)$fatal(1,"controller request overflow");
   last_addr=addr;
  end
  if(last_rd && !rd)begin
   if(burst!=128)$fatal(1,"burst length %d",burst);
   burst=0;
  end
  last_rd=rd;
  if(rst && rp<wp && cycles%2==0 && cycles%1000>=40)begin
   maddr=queue[rp%4096];rp++;bank=maddr/307200;offset=maddr%307200;
   bvalid<=1;bdata<={8'd0,color(bank,offset%640,offset/640)};
  end
 end
 end endgenerate
 integer pixels=0,frames=0,thumb_frames=0,full_frames=0;
 integer x,y,b,sx,sy;reg[23:0]expected;reg prev_vs=1,prev_fs=0,prev_mode=0;
 integer focus_seen=0;
 always @(posedge pixclk)if(rst)begin
  if(error!=0 || underflow)$fatal(1,"reader error %h underflow %b frame %d pixel %d",error,underflow,frames,pixels);
  if(mode!=prev_mode && !prev_fs)$fatal(1,"mode changes outside frame boundary");
  prev_mode<=mode;prev_fs<=fs;
  if(prev_vs && !vs)begin
   if(pixels!=0)begin
    if(pixels!=307200)$fatal(1,"short raster %d",pixels);
    frames++;
    $display("FRAME_PASS %d full=%d thumbnails=%d reads=%d",frames,full_frames,thumb_frames,reads);
   end
   pixels=0;
  end
  prev_vs<=vs;
  if(de)begin
   x=pixels%640;y=pixels/640;
   if(vx!=x)$fatal(1,"coordinate misalignment");
   if(pixels==0)begin
    if(mode)begin thumb_frames++;focus_seen|=1<<index;end else full_frames++;
   end
   expected=adjust_color(color(index,x,y));
   if(EMERGENCY_TEST && emergency_missing)expected=24'h300000;
   if(mode)begin
    expected=0;
    if(x<320 && y<240)begin
     b=(y/120)*2+x/160;sx=x%160;sy=y%120;
     expected=adjust_color(color(b,sx*4,sy*4));
     if(b==index && (sx<2 || sx>=158 || sy<2 || sy>=118))expected=24'hffff00;
    end
   end
   if(rgb!==expected)$fatal(1,"RGB mode=%b index=%d x=%d y=%d got=%h expected=%h",mode,index,x,y,rgb,expected);
   pixels++;
  end
 end
 task toggle_mode;
  // Intentionally request in active video, never at a frame boundary.
  begin wait(de);repeat(175)@(negedge pixclk);
   @(negedge ctrlclk);toggle=1;@(negedge ctrlclk);toggle=0;
  end
 endtask
 task next_image;
  begin @(negedge ctrlclk);next_event=1;@(negedge ctrlclk);next_event=0;end
 endtask
 task params(input integer b,c);
  begin @(negedge vs);brightness=b;contrast=c;repeat(2)@(negedge vs);end
 endtask
 initial begin
  #100;rst=1;
  if(EMERGENCY_TEST)begin
   // Exercise real frame-atomic takeover and restore, not forced internals.
   brightness=192;contrast=128;
   wait(frames==1);wait(de);repeat(175)@(negedge pixclk);emergency_request=1;
   wait(emergency_active);wait(frames>=3);
   if(index!=3 || emergency_missing || !crc_checked[3] || crc_fault)$fatal(1,"emergency takeover/CRC failed");
   params(128,128);params(255,128);params(192,160);
   @(negedge vs);complete_images=7;repeat(2)@(negedge vs);
   if(!emergency_missing)$fatal(1,"missing emergency image not signaled");
   complete_images=15;repeat(2)@(negedge vs);
   if(emergency_missing)$fatal(1,"emergency image missing flag stuck");
   wait(de);repeat(175)@(negedge pixclk);emergency_request=0;
   wait(!emergency_active);repeat(2)@(negedge vs);
   if(index!=0 || crc_fault || error || underflow)$fatal(1,"normal restoration failed");
   $display("TB_PASS emergency brightness pipeline: exact full-frame normal/alarm shared transform b192/128/255 c128/160, CRC unchanged, missing fallback, mid-frame request/restore, frames=%0d",frames);
   $finish;
  end
  if(QUICK)begin
   wait(frames==1);brightness=128;contrast=192;
   toggle_mode();wait(mode);wait(thumb_frames>=1);wait(pixels==307200);
   toggle_mode();wait(!mode);
   for(integer bank=1;bank<4;bank++)begin
    next_image();wait(index==bank);wait(de && pixels==1);wait(pixels==307200);
   end
   repeat(12)@(negedge pixclk);
   if(thumb_frames<1 || full_frames<4)$fatal(1,"quick coverage");
   if(INJECT)begin
    if(!crc_fault || crc_index!=0 || crc_expected!=32'h0000ba73 || crc_actual!=32'h0000b2c4)$fatal(1,"corruption capture");
   end else if(crc_checked!=15 || crc_fault)$fatal(1,"false/incomplete CRC checked%h actual%h",crc_checked,crc_actual);
   $display("TB_PASS CRC pipeline all four full-image banks, thumbnails, brightness/contrast, pixel oracle, INJECT=%d checked=%h actual=%h",INJECT,crc_checked,crc_actual);
   $finish;
  end
  if(SMOKE_ONLY)begin
   wait(mem_ready);repeat(20)@(negedge ctrlclk);toggle=1;@(negedge ctrlclk);toggle=0;
   wait(thumb_frames==1);@(negedge vs);#1;
   if(pixels!=307200 || reads!=307200)$fatal(1,"physical coverage pixels=%d reads=%d",pixels,reads);
   $display("TB_PASS real encrypted SDRAM controller, full 640x480 raster, four thumbnails, row/bank jumps, refresh and FIFO; pixels=%d reads=%d",pixels,reads);
   $finish;
  end
  wait(frames==1);params(128,255);toggle_mode();wait(mode);wait(thumb_frames==2);
  params(255,0);params(0,128);params(64,192);
  for(integer k=1;k<=4;k++)begin
   next_image();wait(index==(k%4));repeat(2)@(negedge vs);
  end
  toggle_mode();wait(!mode);repeat(2)@(negedge vs);params(255,128);
  toggle_mode();wait(mode);repeat(2)@(negedge vs);
  toggle_mode();wait(!mode);repeat(2)@(negedge vs);
  if(focus_seen!=15 || thumb_frames<6 || full_frames<3)$fatal(1,"coverage incomplete");
  if(DIAG)begin
   if(!crc_checked[0])$fatal(1,"display probe never completed normal frame");
   if(INJECT)begin
    if(!crc_fault || crc_index!=0 || crc_actual==crc_expected)$fatal(1,"memory corruption not detected");
   end else if(crc_fault)$fatal(1,"false CRC fault in full/thumbnail/parameter transitions %h",crc_actual);
  end
  $display("CRC_PIPELINE_PASS DIAG=%d INJECT=%d checked=%h actual=%h",DIAG,INJECT,crc_checked,crc_actual);
  $display("TB_PASS adjusted full raster and four thumbnails, all focus banks, neutral/dark/gray/clipping, black background and unadjusted yellow border, mode changes; frames=%d",frames);
  $finish;
 end
 initial begin #800000000;$fatal(1,"picture pipeline timeout");end
endmodule
