`timescale 1ns/1ps
// MiCu debounce / press-duration method; repeat while held, short on release.
module k3_hold_control #(
 parameter integer CLKS_PER_MS=100000, DEBOUNCE_MS=20,
 parameter integer LONG_MS=600, REPEAT_MS=60
)(input wire clk,rst_n,key_n,enable,emergency,
 output wire select_event,step_event);
 reg select_pulse,step_pulse;
 reg [1:0] key_sync;
 reg [16:0] divider;
 reg [4:0] debounce;
 reg stable_n,pressed,long_seen,armed,scene_q;
 reg [9:0] duration;
 reg [6:0] repeat_count;
 wire ms_tick=divider==CLKS_PER_MS-1;
 assign select_event=select_pulse && enable && scene_q==emergency;
 assign step_event=step_pulse && enable && scene_q==emergency;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   key_sync<=3;divider<=0;debounce<=0;stable_n<=1;
   pressed<=0;long_seen<=0;armed<=0;scene_q<=0;
   duration<=0;repeat_count<=0;select_pulse<=0;step_pulse<=0;
  end else begin
   key_sync<={key_sync[0],key_n};
   divider<=ms_tick ? 0 : divider+1'b1;
   select_pulse<=0;step_pulse<=0;scene_q<=emergency;
   if(ms_tick)begin
    if(key_sync[1]==stable_n)debounce<=0;
    else if(debounce==DEBOUNCE_MS-1)begin stable_n<=key_sync[1];debounce<=0;end
    else debounce<=debounce+1'b1;
   end
   // A scene change, reset or loading cancels this gesture; require release.
   if(!enable || scene_q!=emergency)begin
    armed<=0;pressed<=0;long_seen<=0;duration<=0;repeat_count<=0;
   end else if(ms_tick)begin
    if(!armed)begin
     if(stable_n && key_sync[1] && debounce==0)armed<=1;
    end else if(!pressed)begin
     if(!stable_n)begin pressed<=1;duration<=0;long_seen<=0;repeat_count<=0;end
    end else if(stable_n)begin
     pressed<=0;
     if(!long_seen)select_pulse<=1;
    end else if(!key_sync[1])begin
     // Stop repeats as soon as a synchronized release is seen, not 20ms later.
     if(!long_seen)begin
      if(duration==LONG_MS-1)begin long_seen<=1;step_pulse<=1;repeat_count<=0;end
      else duration<=duration+1'b1;
     end else if(repeat_count==REPEAT_MS-1)begin step_pulse<=1;repeat_count<=0;end
     else repeat_count<=repeat_count+1'b1;
    end
   end
  end
 end
endmodule
