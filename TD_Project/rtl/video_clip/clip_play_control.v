`timescale 1ns/1ps
// SW1 high loops the preloaded clip; low cancels at the next frame boundary.
// Restart is a one-cycle pulse for the voice player, with no active-video gap.
module clip_play_control #(
 parameter integer DEBOUNCE_FRAMES=3, FRAME_CYCLES=2500000, FRAMES=20,
 parameter [20:0]BASE_WORD=21'd1228800,FRAME_WORDS=21'd19200
)(
 input wire clk,rst_n,switch_in,ready,frame_start,blocked,emergency,
 output reg active,output reg restart,output reg[4:0]frame_index,output reg[20:0]frame_base
);
 localparam DBW=DEBOUNCE_FRAMES<=1 ? 1 : DEBOUNCE_FRAMES-1;
 localparam TW=FRAME_CYCLES<2 ? 1 : $clog2(FRAME_CYCLES);
 reg sw_meta,sw_sync,sw_stable,armed,pending,step_pending,stop_pending;
 reg[DBW-1:0]sw_history;reg[TW-1:0]timer;reg[4:0]ticks;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   sw_meta<=0;sw_sync<=0;sw_stable<=0;sw_history<=0;armed<=1;pending<=0;restart<=0;
   active<=0;frame_index<=0;frame_base<=BASE_WORD;timer<=0;ticks<=0;step_pending<=0;stop_pending<=0;
  end else begin
   restart<=0;sw_meta<=switch_in;sw_sync<=sw_meta;
   // Three equal frame-boundary samples replace a 19-bit debounce counter.
   // The zero setting is only used to accelerate full-raster integration tests.
   if(DEBOUNCE_FRAMES==0)sw_stable<=sw_sync;
   else if(frame_start)begin
    sw_history<=(sw_history<<1)|sw_sync;
    if(DEBOUNCE_FRAMES==1 || (&sw_history && sw_sync) || (!(|sw_history) && !sw_sync))sw_stable<=sw_sync;
   end
   if(!sw_stable)begin armed<=1;pending<=0;end
   else if(armed && ready && !blocked && !emergency)begin armed<=0;pending<=1;end
   if(emergency || !ready)begin pending<=0;armed<=1;end
   if(active && !stop_pending)begin
    if(timer==FRAME_CYCLES-1)begin
     timer<=0;ticks<=ticks+1'b1;
     if(ticks==FRAMES-1)stop_pending<=1;else step_pending<=1;
    end else timer<=timer+1'b1;
   end
   if(frame_start)begin
    if(emergency || !ready || !sw_stable)begin
     active<=0;step_pending<=0;stop_pending<=0;timer<=0;ticks<=0;
    end else if(!active && pending && !blocked)begin
     active<=1;pending<=0;frame_index<=0;frame_base<=BASE_WORD;
     step_pending<=0;stop_pending<=0;timer<=0;ticks<=0;
    end else if(active && stop_pending)begin
     frame_index<=0;frame_base<=BASE_WORD;restart<=1;
     step_pending<=0;stop_pending<=0;timer<=0;ticks<=0;
    end else if(active && step_pending)begin
     frame_index<=frame_index+1'b1;frame_base<=frame_base+FRAME_WORDS;
     // Keep a newly arriving tick if it coincides with committing an older one.
     step_pending<=timer==FRAME_CYCLES-1 && !stop_pending && ticks!=FRAMES-1;
    end
   end
  end
 end
endmodule
