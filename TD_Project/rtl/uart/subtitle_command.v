`timescale 1ns/1ps
// MiCu lesson 10 line/execute/response contract, adapted to subtitles.
// One outstanding CRLF command. Host must wait for the full reply.
module subtitle_command #(parameter integer ENABLE_EMERGENCY_LOCK=0,ENABLE_PANEL=0)(
 input wire clk,rst_n,rx_valid,line_abort,frame_start,response_ready,
 input wire[7:0]rx_data,
 input wire subtitle_locked,
 input wire panel_done,panel_ok,
 output reg panel_valid,output reg[2:0]panel_op,output reg[7:0]panel_value,
 output reg response_valid,
 output reg[2:0]response_id,
 output reg[255:0]text_bytes,
 output reg[5:0]text_length,
 output reg subtitle_enable,restart_toggle,
 output reg emergency_set_valid,emergency_set_value,
 output reg overflow
);
 reg[295:0]line;
 reg[5:0]length;
 reg bad,saw_cr,waiting_frame,waiting_emergency;
 reg waiting_panel;
 function[4:0]hex_digit;
  input[7:0]c;
  begin
   if(c>="0" && c<="9")hex_digit={1'b0,c[3:0]};
   else if(c>="A" && c<="F")hex_digit=c-8'd55;
   else hex_digit=5'h10;
  end
 endfunction
 wire[4:0]hex_hi=hex_digit(line[55:48]),hex_lo=hex_digit(line[63:56]);
 wire[7:0]hex_value={hex_hi[3:0],hex_lo[3:0]};
 // Existing glyph IDs: campus safety education, please pass courteously (12 chars).
 localparam [255:0] DEFAULT_TEXT=256'ha2a1adac9a20959493929190;
 localparam [5:0] DEFAULT_LENGTH=6'd12;
 wire command_ready=!waiting_frame && !waiting_panel && response_ready && !response_valid;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   line<=0;length<=0;bad<=0;saw_cr<=0;waiting_frame<=0;
   response_valid<=0;response_id<=1;overflow<=0;
   waiting_emergency<=0;emergency_set_valid<=0;emergency_set_value<=0;
   waiting_panel<=0;panel_valid<=0;panel_op<=0;panel_value<=0;
   text_bytes<=DEFAULT_TEXT;text_length<=DEFAULT_LENGTH;subtitle_enable<=1;restart_toggle<=0;
  end else begin
   response_valid<=0;
   emergency_set_valid<=0;
   panel_valid<=0;
   if(ENABLE_PANEL && waiting_panel && panel_done)begin
    waiting_panel<=0;response_valid<=1;response_id<=panel_ok ? 3'd0 : 3'd1;
   end
   // The overlay captures the complete pending bundle on this same VS edge.
   // Allow the request latch to consume set_valid before acknowledging a frame.
   if(waiting_frame && frame_start && !emergency_set_valid)begin
    waiting_frame<=0;waiting_emergency<=0;response_valid<=1;
    response_id<=waiting_emergency ? 3'd4 : 3'd0;
   end
   if(line_abort)begin
    length<=0;saw_cr<=0;bad<=1; // Discard damaged line through its newline.
   end else if(rx_valid)begin
    if(rx_data==8'h0d)begin
     saw_cr<=1;
     if(saw_cr)bad<=1;
    end else if(rx_data==8'h0a)begin
     length<=0;saw_cr<=0;bad<=0;line<=0;
     if(!command_ready)overflow<=1;
     else if(bad || !saw_cr)begin response_valid<=1;response_id<=1;end
     else if(ENABLE_EMERGENCY_LOCK && subtitle_locked &&
       ((length>=6 && line[39:0]==" TXET") ||
        (length==6 && line[47:0]=="NO BUS") ||
        (length==7 && line[55:0]=="FFO BUS") ||
        (length==9 && line[71:0]=="TESER BUS")))begin
      response_valid<=1;response_id<=1;
     end else if(length>=6 && line[39:0]==" TXET")begin
      text_bytes<=line[295:40];text_length<=length-6'd5;
      restart_toggle<=!restart_toggle;waiting_frame<=1;
     end else if(length==6 && line[47:0]=="NO BUS")begin
      subtitle_enable<=1;waiting_frame<=1;
     end else if(length==7 && line[55:0]=="FFO BUS")begin
      subtitle_enable<=0;waiting_frame<=1;
     end else if(length==9 && line[71:0]=="TESER BUS")begin
      text_bytes<=DEFAULT_TEXT;text_length<=DEFAULT_LENGTH;subtitle_enable<=1;
      restart_toggle<=!restart_toggle;waiting_frame<=1;
     end else if(length==6 && line[47:0]=="SUTATS")begin
      response_valid<=1;response_id<=subtitle_enable ? 3'd2 : 3'd3;
     end else if(length==6 && line[47:0]=="NO GME")begin
      emergency_set_valid<=1;emergency_set_value<=1;
      waiting_frame<=1;waiting_emergency<=1;
     end else if(length==7 && line[55:0]=="FFO GME")begin
      emergency_set_valid<=1;emergency_set_value<=0;
      waiting_frame<=1;waiting_emergency<=1;
     end else if(length==10 && line[79:0]=="SUTATS GME")begin
      response_valid<=1;response_id<=4;
     end else if(ENABLE_PANEL && length==11 && line[87:0]=="SUTATS LRTC")begin
      response_valid<=1;response_id<=5;
     end else if(ENABLE_PANEL && ((length==8 && line[63:0]=="TXEN CIP") ||
        (length==8 && line[63:0]=="VERP CIP") ||
        (length==7 && line[55:0]=="NO YALP") ||
        (length==8 && line[63:0]=="FFO YALP")))begin
      panel_op<=line[63:0]=="TXEN CIP" ? 1 : line[63:0]=="VERP CIP" ? 2 : 3;
      panel_value<=line[55:0]=="NO YALP" ? 1 : 0;
      panel_valid<=1;waiting_panel<=1;
     end else if(ENABLE_PANEL && length==8 && line[31:0]==" TES" && line[47:40]==" " &&
       !hex_hi[4] && !hex_lo[4] &&
       ((line[39:32]=="B" && hex_value>=128) ||
        (line[39:32]=="C" && hex_value>=96 && hex_value<=160) || line[39:32]=="V"))begin
      panel_op<=line[39:32]=="B" ? 4 : line[39:32]=="C" ? 5 : 6;
      panel_value<=hex_value;panel_valid<=1;waiting_panel<=1;
     end else begin response_valid<=1;response_id<=1;end
    end else begin
     // Glyph IDs are allowed only inside TEXT, never command names.
     if(saw_cr || !((rx_data>=8'h20 && rx_data<=8'h7e) ||
        (length>=5 && line[39:0]==" TXET" &&
         (rx_data==8'h89 || rx_data==8'h8a || (rx_data>=8'h90 && rx_data<=8'haf)))))bad<=1;
     saw_cr<=0;
     if(length<37)begin line[length*8+:8]<=rx_data;length<=length+1'b1;end
     else bad<=1;
    end
   end
  end
 end
endmodule
