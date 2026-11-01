`timescale 1ns/1ps
// The exact existing overlay modules receive masked rendering enables only.
// Their RGB pass-through must stay bit-exact while real video DE continues.
module tb_clip_overlay;
 reg clk=0,rst=0,vs=1,de=0,clip=0;reg[9:0]x=0;reg[23:0]input_rgb=0;
 always #20 clk=~clk;
 wire render_de=de && !clip;
 wire[23:0]a,b,c,d,e;
 osd_overlay_24 #(.ENABLE_PICTURE_PARAMS(0)) o0(
  .clk(clk),.rst_n(rst),.vsync(vs),.de(render_de),.rgb_in(input_rgb),.pixel_x(x),
  .active_index(2'd1),.auto_enabled(1'b1),.picture_brightness(8'd192),.picture_contrast(8'd128),.picture_menu(1'b0),
  .error_code(8'd0),.rgb_out(a),.de_out(),.osd_active());
 dynamic_subtitle_overlay #(.UART_CONTROL(1),.WALL_TIME(1)) o1(
  .clock_valid(1'b1),.clock_bcd(24'h123456),.clk(clk),.rst_n(rst),.vsync(vs),.de(render_de),.enable(1'b1),
  .pixel_x(x),.rgb_in(a),.active_index(2'd1),.rgb_out(b),.uart_text(256'h4142434445464748),
  .uart_length(6'd8),.uart_enable(1'b1),.uart_restart(1'b0));
 promax_audio_waveform o2(.clk(clk),.rst_n(rst),.vsync(vs),.de(de),.rgb_in(b),.pixel_x(x),
  .enable(!clip),.pcm_tap_valid(1'b0),.pcm_tap_left(16'd0),.rgb_out(c),.waveform_active());
 k3_params_osd o3(.clk(clk),.rst_n(rst),.vsync(vs),.de(render_de),.emergency(1'b0),.legacy_menu(1'b0),
  .pixel_x(x),.rgb_in(c),.brightness(8'd192),.contrast(8'd128),.volume(8'd255),.selected(2'd0),.rgb_out(d));
 period_setting_osd o4(.ctrl_clk(clk),.ctrl_rst_n(rst),.show_ctrl(1'b1),.bcd_ctrl(8'h03),
  .clk(clk),.rst_n(rst),.vsync(vs),.de(render_de),.emergency(1'b0),.pixel_x(x),.rgb_in(d),.rgb_out(e));
 integer hits=0,clip_pixels=0;
 task render(input integer mode);
  begin
   clip=mode;vs=0;de=0;repeat(10)@(negedge clk);vs=1;
   for(integer yy=0;yy<20;yy++)begin
    for(integer xx=0;xx<800;xx++)begin
     @(negedge clk);x=xx;de=xx<640;input_rgb={8'(xx),8'(yy*13),8'(xx^yy)};#1;
     if(mode && de)begin
      if(e!==input_rgb)$fatal(1,"clip overlay changed RGB x%0d y%0d input%h actual%h",xx,yy,input_rgb,e);
      clip_pixels++;
     end else if(de && e!==input_rgb)hits++;
    end
   end
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;repeat(30)@(negedge clk);
  render(0);if(hits==0)$fatal(1,"normal overlays never rendered");
  hits=0;render(1);
  render(0);if(hits==0 || clip_pixels!=12800)$fatal(1,"overlay restoration/count");
  $display("TB_PASS clip overlay passthrough: all 12800 RGB values exact with actual status/subtitle/time/waveform/parameter modules; original overlays resume afterward");$finish;
 end
 initial begin #3000000;$fatal(1,"timeout");end
endmodule
