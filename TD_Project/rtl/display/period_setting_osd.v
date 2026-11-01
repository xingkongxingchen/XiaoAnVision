`timescale 1ns/1ps
// Same held-mailbox/frame-boundary handshake as picture_adjust_control.
// Transparent 16x16 label at (16,74), below parameter bars, above poster text.
module period_setting_osd(
 input wire ctrl_clk,ctrl_rst_n,show_ctrl,input wire[7:0]bcd_ctrl,
 input wire clk,rst_n,vsync,de,emergency,input wire[9:0]pixel_x,
 input wire[23:0]rgb_in,output reg[23:0]rgb_out
);
 reg[8:0]mailbox;
 reg request,ack;
 reg[1:0]ack_sync,req_sync;
 reg[8:0]view;
 reg vs_q,de_q;
 reg[9:0]line_y;
 wire frame_start=vs_q && !vsync;
 always @(posedge ctrl_clk or negedge ctrl_rst_n)begin
  if(!ctrl_rst_n)begin mailbox<={1'b0,8'h03};request<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};
   if(request==ack_sync[1] && mailbox!={show_ctrl,bcd_ctrl})begin
    mailbox<={show_ctrl,bcd_ctrl};request<=~request;
   end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin req_sync<=0;ack<=0;view<={1'b0,8'h03};vs_q<=1;de_q<=0;line_y<=0;end
  else begin
   req_sync<={req_sync[0],request};vs_q<=vsync;de_q<=de;
   if(!vsync)line_y<=0;else if(de_q && !de)line_y<=line_y+1'b1;
   if(frame_start && req_sync[1]!=ack)begin view<=mailbox;ack<=req_sync[1];end
  end
 end
 // Generated from SimSun by scripts/generate_period_font.ps1.
 function[255:0]font_bits;
  input[4:0]id;
  begin case(id)
   0:font_bits=256'h2040204020a0fca0411052089406fd10112011401d80f1005104110410fc1000;
   1:font_bits=256'h207827c022482150fbfc215022482c0633f8e248224823f822482248a3f84208;
   2:font_bits=256'h200013fc1004400447c444444444444447c444444444444447c4400440144008;
   3:font_bits=256'h00007bfe480051fc5104610451fc48004bfe4a8a6a5253fe42224222422a4204;
   4:font_bits=256'h0000000000000000000000000000000000003000300000003000300000000000;
   5:font_bits=256'h08201c20f02010a810a4fca2112231203a245424542890081010102010c01300;
   6:font_bits=256'h0000000000001800240042004200420042004200420042002400180000000000;
   7:font_bits=256'h00000000000008003800080008000800080008000800080008003e0000000000;
   8:font_bits=256'h0000000000003c004200420042000200040008001000200042007e0000000000;
   9:font_bits=256'h0000000000003c004200420002000400180004000200420042003c0000000000;
   10:font_bits=256'h00000000000004000c000c0014002400240044007f00040004001f0000000000;
   11:font_bits=256'h0000000000007e00400040004000780044000200020042004400380000000000;
   12:font_bits=256'h00000000000018002400400040005c00620042004200420022001c0000000000;
   13:font_bits=256'h0000000000007e00420004000400080008001000100010001000100000000000;
   14:font_bits=256'h0000000000003c004200420042002400180024004200420042003c0000000000;
   15:font_bits=256'h0000000000003800440042004200420046003a00020002002400180000000000;
   default:font_bits=0;
  endcase end
 endfunction
 wire[9:0]dx=pixel_x-10'd16;
 wire[9:0]dy=line_y-10'd74;
 reg[4:0]id;
 reg[255:0]bits;
 always @*begin
  case(dx[6:4])
   0:id=0;1:id=1;2:id=2;3:id=3;4:id=4;
   5:id=5'd6+{1'b0,view[7:4]};6:id=5'd6+{1'b0,view[3:0]};default:id=5;
  endcase
  bits=font_bits(id);rgb_out=rgb_in;
  if(de && view[8] && !emergency && pixel_x>=16 && pixel_x<144 && dy<16 &&
     bits[8'd255-{dy[3:0],dx[3:0]}])rgb_out=24'hff0000;
 end
endmodule
