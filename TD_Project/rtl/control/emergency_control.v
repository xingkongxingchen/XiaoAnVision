`timescale 1ns/1ps
// Application control only; does not reset or alter the media pipeline.
module emergency_control #(
 parameter integer DEBOUNCE_CYCLES = 500000
)(
 input wire clk, rst_n,
 input wire switch_async,
 input wire uart_set_valid, uart_set_value,
 input wire frame_start,
 output wire [1:0] source,
 output wire requested,
 output reg active,
 output reg entered, exited
);
 localparam integer COUNT_BITS = (DEBOUNCE_CYCLES <= 1) ? 1 : $clog2(DEBOUNCE_CYCLES);
 reg switch_meta, switch_sync, switch_stable;
 reg [COUNT_BITS-1:0] stable_count;
 reg uart_request;

 assign source = {uart_request, switch_stable};
 assign requested = |source;

 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   switch_meta <= 0; switch_sync <= 0;
   switch_stable <= 0; stable_count <= 0;
   uart_request <= 0;
   active <= 0; entered <= 0; exited <= 0;
  end else begin
   switch_meta <= switch_async;
   switch_sync <= switch_meta;
   if (switch_sync == switch_stable) stable_count <= 0;
   else if (stable_count == DEBOUNCE_CYCLES - 1) begin
    switch_stable <= switch_sync;
    stable_count <= 0;
   end else stable_count <= stable_count + 1'b1;

   if (uart_set_valid) uart_request <= uart_set_value;
   entered <= 0; exited <= 0;
   if (frame_start) begin
    active <= requested;
    entered <= requested && !active;
    exited <= !requested && active;
   end
  end
 end
endmodule
