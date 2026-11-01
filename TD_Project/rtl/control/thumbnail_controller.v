`timescale 1ns/1ps
// MiCu lesson 15: independent focus, confirm selection, cancel without change.
// Reuse the player's existing index request/ack; never drive active_index here.
module thumbnail_controller #(
 parameter integer ENABLE_EMERGENCY=0
)(
 input wire clk,rst_n,enable,
 input wire key_right,key_left,key_confirm,key_mode,
 input wire[3:0]image_complete,
 input wire[1:0]current_index,
 input wire player_busy,fade_busy,
 input wire cancel,
 output wire browse_active,
 output reg select_event,output reg[1:0]select_index,
 input wire pix_clk,pix_rst_n,frame_start,
 output reg view_mode,output reg[1:0]focus_index
);
 localparam FULL=0,THUMB=1,WAIT_BUSY=2,WAIT_DONE=3,EXIT_SYNC=4;
 reg[2:0]state;
 reg enter_pending;
 reg[1:0]focus;
 wire desired_mode=(state==THUMB || state==WAIT_BUSY || state==WAIT_DONE);
 assign browse_active=(state!=FULL)||enter_pending;
 reg[2:0]mailbox;
 reg request,ack;
 reg[1:0]ack_sync,req_sync;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=FULL;enter_pending<=0;focus<=0;select_event<=0;select_index<=0;
  end else begin
   select_event<=0;
   if(ENABLE_EMERGENCY && cancel)begin state<=FULL;enter_pending<=0;focus<=0;end
   else if(enable)case(state)
    FULL:begin
     if(key_mode)enter_pending<=~enter_pending;
     else if(enter_pending && !player_busy && !fade_busy)begin
      focus<=current_index;state<=THUMB;enter_pending<=0;
     end
    end
    THUMB:begin
     if(key_mode)state<=EXIT_SYNC;
     else if(key_confirm && image_complete[focus] && !player_busy && !fade_busy)begin
      select_index<=focus;select_event<=1;state<=WAIT_BUSY;
     end else if(key_right)focus<=ENABLE_EMERGENCY && focus==2 ? 0 : focus+1'b1;
     else if(key_left)focus<=ENABLE_EMERGENCY && focus==0 ? 2 : focus-1'b1;
    end
    WAIT_BUSY:if(player_busy)state<=WAIT_DONE;
    WAIT_DONE:if(!player_busy)state<=EXIT_SYNC;
    EXIT_SYNC:if(mailbox=={1'b0,focus} && request==ack_sync[1])state<=FULL;
    default:state<=FULL;
   endcase
  end
 end
 // Atomic mode/focus mailbox. Sender holds the entire bundle until the
 // receiver acknowledges a frame-boundary commit. Rapid moves coalesce.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin mailbox<=0;request<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};
   if(request==ack_sync[1] && mailbox!={desired_mode,focus})begin
    mailbox<={desired_mode,focus};request<=~request;
   end
  end
 end
 always @(posedge pix_clk or negedge pix_rst_n)begin
  if(!pix_rst_n)begin req_sync<=0;ack<=0;view_mode<=0;focus_index<=0;end
  else begin
   req_sync<={req_sync[0],request};
   if(frame_start && req_sync[1]!=ack)begin
    {view_mode,focus_index}<=mailbox;ack<=req_sync[1];
   end
  end
 end
endmodule
