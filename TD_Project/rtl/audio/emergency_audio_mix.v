`timescale 1ns/1ps
// Independent 48 kHz output cadence. Keep draining ordinary PCM while the
// resident FPGA cue replaces it; resuming WAV follows its current position.
module emergency_audio_mix #(parameter integer DUAL_MUSIC=0,FADE_BITS=8,
 parameter integer CUE_SAMPLES=120000)(
 input wire clk,rst_n,sample_tick,emergency,
 input wire normal_valid,
 output wire normal_ready,
 input wire signed[15:0]normal_left,normal_right,
 input wire alert_valid,input wire signed[15:0]alert_sample,
 output wire alert_ready,
 output wire out_valid,
 input wire out_ready,
 output wire signed[15:0]out_left,out_right,
 output reg overflow
);
 reg signed[15:0]background_left,background_right;
 reg signed[15:0]alert_held;
 reg[31:0]fifo[0:7];
 reg[2:0]read_pointer,write_pointer;
 reg[3:0]fifo_count;
 wire pop=out_valid && out_ready;
 wire push=sample_tick && (fifo_count<8 || pop);
 assign out_valid=fifo_count!=0;
 assign {out_left,out_right}=fifo[read_pointer];
 reg[FADE_BITS:0]mix_gain;
 reg[5:0]phase;
 reg[14:0]cadence;
 reg[6:0]beep_gain;
 localparam integer CUE_BITS=$clog2(CUE_SAMPLES+1);
 reg[CUE_BITS-1:0]cue_count;
 reg emergency_q;
 reg[FADE_BITS:0]alert_gain;
 wire new_entry=emergency && !emergency_q;
 wire cue_window=new_entry || cue_count<CUE_SAMPLES;
 wire cue_enable=DUAL_MUSIC ? (emergency && cue_window && alert_gain==0) : 1'b1;
 reg signed[15:0]triangle;
 // 48 samples/cycle at 48 kHz: 1 kHz triangle, bounded to +/-3000.
 always @*begin
  if(phase<12)triangle=$signed({1'b0,phase})*16'sd250;
  else if(phase<36)triangle=(16'sd24-$signed({1'b0,phase}))*16'sd250;
  else triangle=($signed({1'b0,phase})-16'sd48)*16'sd250;
 end
 wire signed[23:0]beep_product=triangle*$signed({1'b0,beep_gain});
 wire signed[15:0]beep=beep_product >>> 6;
 // Cue and file envelopes are mutually exclusive: no additive headroom
 // reservation is needed. Unity preserves full signed16 range without boost.
 wire signed[15:0]alert_level=DUAL_MUSIC ? alert_held : 16'sd0;
 // Break-before-make envelopes: never mix the resident cue with file audio.
 wire signed[FADE_BITS+17:0]alert_product=alert_level*$signed({1'b0,alert_gain});
 wire signed[15:0]alert_faded=alert_product >>> FADE_BITS;
 wire signed[15:0]alarm_sample=alert_faded+beep;
 wire[FADE_BITS:0]normal_gain=(1<<FADE_BITS)-mix_gain;
 wire signed[FADE_BITS+17:0]left_normal=background_left*$signed({1'b0,normal_gain});
 wire signed[FADE_BITS+17:0]right_normal=background_right*$signed({1'b0,normal_gain});
 wire signed[FADE_BITS+17:0]alarm_product=alarm_sample*$signed({1'b0,mix_gain});
 wire signed[FADE_BITS+18:0]left_sum={left_normal[FADE_BITS+17],left_normal}+{alarm_product[FADE_BITS+17],alarm_product};
 wire signed[FADE_BITS+18:0]right_sum={right_normal[FADE_BITS+17],right_normal}+{alarm_product[FADE_BITS+17],alarm_product};
 wire signed[15:0]mixed_left=left_sum >>> FADE_BITS;
 wire signed[15:0]mixed_right=right_sum >>> FADE_BITS;
 assign normal_ready=1'b1;
 assign alert_ready=1'b1;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   background_left<=0;background_right<=0;alert_held<=0;mix_gain<=0;phase<=0;cadence<=0;beep_gain<=0;
   cue_count<=0;emergency_q<=0;alert_gain<=0;
   read_pointer<=0;write_pointer<=0;fifo_count<=0;overflow<=0;
  end else begin
   if(pop)read_pointer<=read_pointer+1'b1;
   if(push)begin
    fifo[write_pointer]<={mixed_left,mixed_right};
    write_pointer<=write_pointer+1'b1;
   end else if(sample_tick)overflow<=1;
   case({push,pop})
    2'b10:fifo_count<=fifo_count+1'b1;
    2'b01:fifo_count<=fifo_count-1'b1;
    default:fifo_count<=fifo_count;
   endcase
   if(sample_tick)begin
    emergency_q<=emergency;
    if(!emergency)cue_count<=0;
    else if(new_entry)cue_count<=1;
    else if(cue_count<CUE_SAMPLES)cue_count<=cue_count+1'b1;
    if(DUAL_MUSIC && emergency && !cue_window && beep_gain==0)begin
     if(alert_gain<(1<<FADE_BITS))alert_gain<=alert_gain+1'b1;
    end else if(alert_gain!=0)alert_gain<=alert_gain-1'b1;
    // Produce silence for an absent ordinary sample, never replay stale data
    // indefinitely. Normal sources deliver their next sample after this tick.
    background_left<=0;background_right<=0;alert_held<=0;
    if(emergency && mix_gain<(1<<FADE_BITS))mix_gain<=mix_gain+1'b1;
    else if(!emergency && mix_gain!=0)mix_gain<=mix_gain-1'b1;
    if(emergency || mix_gain!=0)begin
     phase<=phase==47?0:phase+1'b1;
     cadence<=(DUAL_MUSIC && new_entry) ? 0 : cadence==23999?0:cadence+1'b1;
     if(cue_enable && (cadence<12000 || (DUAL_MUSIC && new_entry)))begin if(beep_gain<64)beep_gain<=beep_gain+1'b1;end
     else if(beep_gain!=0)beep_gain<=beep_gain-1'b1;
    end else begin phase<=0;cadence<=0;beep_gain<=0;end
   end
   // New ordinary sample wins if it arrives on the same clock as a tick.
   if(normal_valid)begin background_left<=normal_left;background_right<=normal_right;end
   if(DUAL_MUSIC && alert_valid)alert_held<=alert_sample;
  end
 end
endmodule
