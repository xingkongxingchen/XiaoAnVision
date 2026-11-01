`timescale 1ns/1ps
// MiCu lecture 14 / lesson 13 section 3.2: brightness then signed contrast.
// Use the documented combinational option to preserve the existing video
// bundle latency. Default brightness 255 explicitly bypasses /256 loss.
module brightness_contrast_adjust(
 input wire in_de,input wire[23:0]rgb_in,
 input wire[7:0]brightness,contrast,
 output wire out_de,output wire[23:0]rgb_out
);
 function[7:0]adjust;
  input[7:0]value,b,c;
  reg[15:0]mul;
  reg[7:0]bright;
  reg signed[8:0]center;
  reg signed[17:0]product;
  reg signed[17:0]sum;
  begin
   mul=value*b;
   bright=(b==255) ? value : mul[15:8];
   center=$signed({1'b0,bright})-9'sd128;
   product=center*$signed({1'b0,c});
   sum=(product >>> 7)+18'sd128;
   adjust=(sum<0) ? 8'd0 : (sum>255) ? 8'd255 : sum[7:0];
  end
 endfunction
 assign rgb_out={adjust(rgb_in[23:16],brightness,contrast),
                 adjust(rgb_in[15:8],brightness,contrast),
                 adjust(rgb_in[7:0],brightness,contrast)};
 assign out_de=in_de;
endmodule
