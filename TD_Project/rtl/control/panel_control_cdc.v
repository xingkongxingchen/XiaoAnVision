`timescale 1ns/1ps
// One outstanding bundled request, held until acknowledgement across 25/100MHz.
module panel_control_cdc(
 input wire pix_clk,pix_rst_n,request_valid,
 input wire[2:0]request_op,input wire[7:0]request_value,
 output reg response_done,response_ok,
 input wire ctrl_clk,ctrl_rst_n,enable,emergency,controls_busy,
 output reg next_event,prev_event,auto_valid,auto_value,param_valid,
 output reg[1:0]param_id,output reg[7:0]param_value
);
 reg request,ack,result;
 reg[10:0]mailbox;
 reg[1:0]req_sync,ack_sync;
 reg pending;
 always @(posedge pix_clk or negedge pix_rst_n)begin
  if(!pix_rst_n)begin request<=0;mailbox<=0;ack_sync<=0;pending<=0;response_done<=0;response_ok<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};response_done<=0;
   if(request_valid && !pending)begin
    mailbox<={request_op,request_value};request<=~request;pending<=1;
   end
   if(pending && ack_sync[1]==request)begin
    response_done<=1;response_ok<=result;pending<=0;
   end
  end
 end
 wire[2:0]op=mailbox[10:8];
 wire[7:0]value=mailbox[7:0];
 wire allowed=enable && (op==6 || (!emergency &&
   ((op==4 || op==5) || ((op==1 || op==2 || op==3) && !controls_busy))));
 always @(posedge ctrl_clk or negedge ctrl_rst_n)begin
  if(!ctrl_rst_n)begin req_sync<=0;ack<=0;result<=0;next_event<=0;prev_event<=0;
   auto_valid<=0;auto_value<=0;param_valid<=0;param_id<=0;param_value<=0;end
  else begin
   req_sync<={req_sync[0],request};next_event<=0;prev_event<=0;auto_valid<=0;param_valid<=0;
   if(req_sync[1]!=ack)begin
    ack<=req_sync[1];result<=allowed;
    if(allowed)case(op)
     1:next_event<=1;
     2:prev_event<=1;
     3:begin auto_valid<=1;auto_value<=value[0];end
     default:begin param_valid<=1;param_id<=op-4;param_value<=value;end
    endcase
   end
  end
 end
endmodule
