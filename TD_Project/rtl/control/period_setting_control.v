`timescale 1ns/1ps
// MiCu lesson 3 release-event method, with the K3 controller's ms debounce.
// A mode change cancels any held gesture; both keys must be released to rearm.
module period_setting_control #(
 parameter integer CLK_HZ=100000000, DEBOUNCE_MS=20
)(
 input wire clk,rst_n,enable,emergency,switch_in,key_plus_n,key_minus_n,
 output wire setting_mode,normal_keys_enabled,
 output reg period_valid,
 output wire[31:0]period_cycles,
 output reg[5:0]period_seconds,
 output reg[7:0]period_bcd
);
 localparam integer MS_CYCLES=CLK_HZ/1000;
 localparam integer TICK_BITS=MS_CYCLES>1 ? $clog2(MS_CYCLES) : 1;
 localparam integer DB_BITS=DEBOUNCE_MS>1 ? $clog2(DEBOUNCE_MS+1) : 1;
 reg[TICK_BITS-1:0]divider;
 reg[1:0]switch_sync,plus_sync,minus_sync;
 reg switch_stable,plus_stable_n,minus_stable_n;
 reg[DB_BITS-1:0]switch_count,plus_count,minus_count;
 wire ms_tick=divider==MS_CYCLES-1;
 reg armed,mode_q;
 reg[1:0]gesture;
 // The 1..30 range fits one five-input LUT per output bit. Enumerate the
 // constant products so TD need not build a general shift/add multiplier.
 // Seconds remain the only setting state; there is no duplicate 32-bit state.
 function[31:0]seconds_to_cycles;
  input[4:0]seconds;
  begin case(seconds)
   1:seconds_to_cycles=32'd1*CLK_HZ;2:seconds_to_cycles=32'd2*CLK_HZ;
   3:seconds_to_cycles=32'd3*CLK_HZ;4:seconds_to_cycles=32'd4*CLK_HZ;
   5:seconds_to_cycles=32'd5*CLK_HZ;6:seconds_to_cycles=32'd6*CLK_HZ;
   7:seconds_to_cycles=32'd7*CLK_HZ;8:seconds_to_cycles=32'd8*CLK_HZ;
   9:seconds_to_cycles=32'd9*CLK_HZ;10:seconds_to_cycles=32'd10*CLK_HZ;
   11:seconds_to_cycles=32'd11*CLK_HZ;12:seconds_to_cycles=32'd12*CLK_HZ;
   13:seconds_to_cycles=32'd13*CLK_HZ;14:seconds_to_cycles=32'd14*CLK_HZ;
   15:seconds_to_cycles=32'd15*CLK_HZ;16:seconds_to_cycles=32'd16*CLK_HZ;
   17:seconds_to_cycles=32'd17*CLK_HZ;18:seconds_to_cycles=32'd18*CLK_HZ;
   19:seconds_to_cycles=32'd19*CLK_HZ;20:seconds_to_cycles=32'd20*CLK_HZ;
   21:seconds_to_cycles=32'd21*CLK_HZ;22:seconds_to_cycles=32'd22*CLK_HZ;
   23:seconds_to_cycles=32'd23*CLK_HZ;24:seconds_to_cycles=32'd24*CLK_HZ;
   25:seconds_to_cycles=32'd25*CLK_HZ;26:seconds_to_cycles=32'd26*CLK_HZ;
   27:seconds_to_cycles=32'd27*CLK_HZ;28:seconds_to_cycles=32'd28*CLK_HZ;
   29:seconds_to_cycles=32'd29*CLK_HZ;30:seconds_to_cycles=32'd30*CLK_HZ;
   default:seconds_to_cycles=32'd3*CLK_HZ;
  endcase end
 endfunction
 assign period_cycles=seconds_to_cycles(period_seconds[4:0]);
 assign setting_mode=enable && !emergency && switch_stable;
 wire context_ok=enable && !emergency && mode_q==setting_mode &&
                 switch_sync[1]==switch_stable;
 assign normal_keys_enabled=context_ok && armed && !setting_mode;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   divider<=0;switch_sync<=0;plus_sync<=3;minus_sync<=3;
   switch_stable<=0;plus_stable_n<=1;minus_stable_n<=1;
   switch_count<=0;plus_count<=0;minus_count<=0;
  end else begin
   switch_sync<={switch_sync[0],switch_in};
   plus_sync<={plus_sync[0],key_plus_n};minus_sync<={minus_sync[0],key_minus_n};
   divider<=ms_tick ? 0 : divider+1'b1;
   if(ms_tick)begin
    if(switch_sync[1]==switch_stable)switch_count<=0;
    else if(switch_count==DEBOUNCE_MS-1)begin switch_stable<=switch_sync[1];switch_count<=0;end
    else switch_count<=switch_count+1'b1;
    if(plus_sync[1]==plus_stable_n)plus_count<=0;
    else if(plus_count==DEBOUNCE_MS-1)begin plus_stable_n<=plus_sync[1];plus_count<=0;end
    else plus_count<=plus_count+1'b1;
    if(minus_sync[1]==minus_stable_n)minus_count<=0;
    else if(minus_count==DEBOUNCE_MS-1)begin minus_stable_n<=minus_sync[1];minus_count<=0;end
    else minus_count<=minus_count+1'b1;
   end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   armed<=0;mode_q<=0;gesture<=0;period_valid<=0;
   period_seconds<=3;period_bcd<=8'h03;
  end else begin
   period_valid<=0;mode_q<=setting_mode;
   if(!context_ok)begin armed<=0;gesture<=0;end
   else if(ms_tick)begin
    if(!armed)begin
     if(plus_stable_n && minus_stable_n && plus_sync[1] && minus_sync[1] &&
        plus_count==0 && minus_count==0)armed<=1;
    end else if(!setting_mode)gesture<=0;
    else case(gesture)
     0:if(!plus_stable_n && !minus_stable_n)gesture<=3;
       else if(!plus_stable_n)gesture<=1;
       else if(!minus_stable_n)gesture<=2;
     1:if(!minus_stable_n)gesture<=3;
       else if(plus_stable_n)begin
        gesture<=0;
        if(period_seconds<30)begin
         period_seconds<=period_seconds+1'b1;period_valid<=1;
         period_bcd<=period_bcd[3:0]==9 ? {period_bcd[7:4]+4'd1,4'd0} : period_bcd+1'b1;
        end
       end
     2:if(!plus_stable_n)gesture<=3;
       else if(minus_stable_n)begin
        gesture<=0;
        if(period_seconds>1)begin
         period_seconds<=period_seconds-1'b1;period_valid<=1;
         period_bcd<=period_bcd[3:0]==0 ? {period_bcd[7:4]-4'd1,4'd9} : period_bcd-1'b1;
        end
       end
     3:if(plus_stable_n && minus_stable_n)gesture<=0;
    endcase
   end
  end
 end
endmodule
