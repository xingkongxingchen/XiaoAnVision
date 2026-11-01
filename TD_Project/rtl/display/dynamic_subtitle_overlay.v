`timescale 1ns/1ps
// Integrate MiCu's scrolling text and timestamp without changing DE/HS/VS.
module dynamic_subtitle_overlay #(
 parameter integer PIXEL_HZ=25000000,
 parameter integer UART_CONTROL=0,
 parameter integer WALL_TIME=0
)(
 input wire clk,rst_n,vsync,de,enable,
 input wire[9:0]pixel_x,input wire[23:0]rgb_in,
 input wire[1:0]active_index,
 input wire[255:0]uart_text,
 input wire[5:0]uart_length,
 input wire uart_enable,uart_restart,
 input wire clock_valid,input wire[23:0]clock_bcd,
 output wire[23:0]rgb_out
);
 reg[11:0]line_y;
 reg de_q;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin line_y<=0;de_q<=0;end
  else begin
   de_q<=de;
   if(!vsync)line_y<=0;
   else if(de_q && !de)line_y<=line_y+1'b1;
  end
 end
 wire[23:0]subtitle_rgb;
 wire[7:0]picture_digit=8'h31+{6'd0,active_index};
 // MiCu byte order: first displayed character occupies bits [7:0].
 // Twelve characters: FPGA IMAGE 1 .. FPGA IMAGE 4.
 wire[95:0]text_bytes={picture_digit," EGAMI AGPF"};
 wire[(UART_CONTROL ? 256 : 96)-1:0]overlay_text=UART_CONTROL ? uart_text : {160'd0,text_bytes};
 promax_text_overlay #(.ENABLE_PARAMS(0),.SUBTITLE_Y(456),
  .MAX_SUBTITLE_CHARS(UART_CONTROL ? 32 : 12),.EXTERNAL_RESTART(UART_CONTROL)) u_text(
  .clk(clk),.rst_n(rst_n),.vsync(vsync),.de(de),.rgb_in(rgb_in),
  .pixel_x(pixel_x),.enable(enable),.subtitle_enable(UART_CONTROL ? uart_enable : 1'b1),
  .subtitle_text(overlay_text),
  .subtitle_length(UART_CONTROL ? uart_length : 6'd12),
  .restart_toggle(UART_CONTROL ? uart_restart : 1'b0),
  .brightness(8'd255),.volume(8'd64),.period_ms(32'd3000),
  .auto_enabled(1'b0),.source_scale_2x(1'b0),
  .rgb_out(subtitle_rgb),.overlay_active());
 timestamp_osd #(.OSD_X(WALL_TIME ? 560 : 584),.OSD_Y(16),.PIXEL_HZ(PIXEL_HZ),.WALL_TIME(WALL_TIME)) u_time(
  .clock_valid(clock_valid),.clock_bcd(clock_bcd),
  .pix_clk(clk),.pix_rst_n(rst_n),.enable(enable),.vsync(vsync),.de(de),
  .pixel_x(pixel_x),.pixel_y(line_y),.rgb_in(subtitle_rgb),.rgb_out(rgb_out),
  .ts_active(),.sys_rst_n(rst_n));
endmodule
