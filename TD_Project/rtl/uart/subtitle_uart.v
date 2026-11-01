`timescale 1ns/1ps
// Byte engines copied unchanged from MiCu UART lessons 7-11.
// Run entirely in video_clk, avoiding a second multi-bit CDC for subtitle text.
module subtitle_uart #(
 parameter integer CLK_FREQ_HZ=25000000,
 parameter integer BAUD_RATE=115200,
 parameter integer DEBOUNCE_CYCLES=500000,
 parameter integer ENABLE_EMERGENCY_LOCK=0,
 parameter integer ENABLE_PANEL=0
)(
 input wire clk,rst_n,rx,vsync,
 input wire emergency_switch,
 input wire scene_takeover,
 input wire panel_done,panel_ok,
 output wire panel_valid,output wire[2:0]panel_op,output wire[7:0]panel_value,
 input wire[1:0]picture_index,input wire autoplay,control_busy,
 input wire[7:0]brightness,contrast,volume,
 output wire emergency_active,
 output wire[1:0]emergency_source,
 output wire tx,
 output wire[255:0]text_bytes,
 output wire[5:0]text_length,
 output wire subtitle_enable,restart_toggle
);
 wire tick,rx_valid,framing_error,tx_start,tx_busy,tx_done;
 wire response_valid,response_ready;
 wire[2:0]response_id;
 wire[7:0]rx_data,tx_data;
 reg vs_q;
 wire emergency_set_valid,emergency_set_value;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)vs_q<=1;else vs_q<=vsync;
 baud_tick #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD_RATE(BAUD_RATE)) u_baud(
  .clk(clk),.rst_n(rst_n),.tick(tick));
 uart_rx #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD_RATE(BAUD_RATE)) u_rx(
  .clk(clk),.rst_n(rst_n),.rx(rx),.data(rx_data),.valid(rx_valid),.framing_error(framing_error));
 subtitle_command #(.ENABLE_EMERGENCY_LOCK(ENABLE_EMERGENCY_LOCK),.ENABLE_PANEL(ENABLE_PANEL)) u_command(.clk(clk),.rst_n(rst_n),.rx_valid(rx_valid),
  .panel_done(panel_done),.panel_ok(panel_ok),.panel_valid(panel_valid),.panel_op(panel_op),.panel_value(panel_value),
  .subtitle_locked(scene_takeover || emergency_active || |emergency_source),
  .rx_data(rx_data),.line_abort(framing_error),.frame_start(vs_q && !vsync),
  .response_ready(response_ready),.response_valid(response_valid),.response_id(response_id),
  .text_bytes(text_bytes),.text_length(text_length),.subtitle_enable(subtitle_enable),
  .restart_toggle(restart_toggle),.overflow(),
  .emergency_set_valid(emergency_set_valid),.emergency_set_value(emergency_set_value));
 emergency_control #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_emergency(
  .clk(clk),.rst_n(rst_n),.switch_async(emergency_switch),
  .uart_set_valid(emergency_set_valid),.uart_set_value(emergency_set_value),
  .frame_start(vs_q && !vsync),.source(emergency_source),.requested(),
  .active(emergency_active),.entered(),.exited());
 emergency_response_tx u_response(.clk(clk),.rst_n(rst_n),.response_valid(response_valid),
  .picture_index(picture_index),.autoplay(autoplay),.control_busy(control_busy),
  .brightness(brightness),.contrast(contrast),.volume(volume),
  .emergency_active(ENABLE_EMERGENCY_LOCK ? scene_takeover : emergency_active),.emergency_source(emergency_source),
  .response_id(response_id),.response_ready(response_ready),.tx_busy(tx_busy),
  .tx_done(tx_done),.tx_start(tx_start),.tx_data(tx_data));
 uart_tx u_tx(.clk(clk),.rst_n(rst_n),.tick(tick),.start(tx_start),.data(tx_data),
  .tx(tx),.busy(tx_busy),.done(tx_done));
endmodule
