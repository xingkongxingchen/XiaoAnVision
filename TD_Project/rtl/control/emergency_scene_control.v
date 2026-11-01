`timescale 1ns/1ps
// Pixel-domain takeover; restoration reuses the normal player's request/ack.
// saved_index is held for the whole takeover, including an interrupted restore.
module emergency_scene_control(
 input wire pix_clk,pix_rst_n,frame_start,requested,
 input wire[1:0]normal_index,
 output reg takeover,
 input wire ctrl_clk,ctrl_rst_n,player_busy,
 output wire block_controls,
 output reg restore_select,
 output wire[1:0]restore_index
);
 reg[1:0]saved_index;
 reg[1:0]take_sync,request_sync,ready_sync;
 reg[1:0]saved_sync1,saved_sync2;
 reg restore_ready;
 reg[1:0]state;
 localparam IDLE=0,WAIT_BUSY=1,WAIT_DONE=2,READY=3;
 assign block_controls=request_sync[1] || take_sync[1] || state!=IDLE;
 assign restore_index=saved_sync2;
 always @(posedge pix_clk or negedge pix_rst_n)begin
  if(!pix_rst_n)begin takeover<=0;saved_index<=0;ready_sync<=0;end
  else begin
   ready_sync<={ready_sync[0],restore_ready};
   if(frame_start)begin
    if(requested && !takeover)begin takeover<=1;saved_index<=normal_index;end
    else if(!requested && takeover && ready_sync[1])takeover<=0;
   end
  end
 end
 always @(posedge ctrl_clk or negedge ctrl_rst_n)begin
  if(!ctrl_rst_n)begin
   take_sync<=0;request_sync<=0;saved_sync1<=0;saved_sync2<=0;
   restore_ready<=0;restore_select<=0;state<=IDLE;
  end else begin
   take_sync<={take_sync[0],takeover};request_sync<={request_sync[0],requested};
   saved_sync1<=saved_index;saved_sync2<=saved_sync1;
   restore_select<=0;
   case(state)
    IDLE:begin
     restore_ready<=0;
     if(take_sync[1] && !request_sync[1] && !player_busy)begin
      restore_select<=1;state<=WAIT_BUSY;
     end
    end
    WAIT_BUSY:if(player_busy)state<=WAIT_DONE;
    WAIT_DONE:if(!player_busy)begin
     if(request_sync[1])state<=IDLE;
     else begin restore_ready<=1;state<=READY;end
    end
    READY:if(request_sync[1] || !take_sync[1])begin restore_ready<=0;state<=IDLE;end
   endcase
  end
 end
endmodule
