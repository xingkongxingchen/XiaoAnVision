`timescale 1ns/1ps
// Application extension of MiCu's one-response/one-byte-at-a-time transmitter.
// The original uart_response_tx.v remains unchanged for reference/regression.
module emergency_response_tx (
 input wire clk,rst_n,response_valid,
 input wire[2:0]response_id,
 input wire emergency_active,
 input wire[1:0]emergency_source,
 input wire[1:0]picture_index,
 input wire autoplay,control_busy,
 input wire[7:0]brightness,contrast,volume,
 output wire response_ready,
 input wire tx_busy,tx_done,
 output reg tx_start,
 output reg[7:0]tx_data
);
 reg active,waiting_done,active_mode;
 reg[1:0]active_source;
 reg[2:0]active_id;
 reg[4:0]byte_index,byte_count;
 reg[1:0]active_picture;
 reg active_auto,active_busy;
 reg[7:0]active_brightness,active_contrast,active_volume;
 function[7:0]hex_char;
  input[3:0]n;
  begin hex_char=n<10 ? 8'h30+{4'd0,n} : 8'h37+{4'd0,n};end
 endfunction
 assign response_ready=!active;
 function[7:0]response_byte;
  input[2:0]kind;
  input[4:0]index;
  input mode;
  input[1:0]source;
  begin
   case(kind)
    0: case(index)
     0:response_byte="O";1:response_byte="K";2:response_byte=13;default:response_byte=10;
    endcase
    1: case(index)
     0:response_byte="E";1,2:response_byte="R";3:response_byte=13;default:response_byte=10;
    endcase
    2: case(index)
     0:response_byte="O";1:response_byte="N";2:response_byte=13;default:response_byte=10;
    endcase
    3: case(index)
     0:response_byte="O";1,2:response_byte="F";3:response_byte=13;default:response_byte=10;
    endcase
    // EMG A1 S3\r\n; coherent snapshot, not live fields during transmission.
    4: case(index)
     0:response_byte="E";1:response_byte="M";2:response_byte="G";
     3,6:response_byte=" ";4:response_byte="A";5:response_byte=mode ? "1" : "0";
     7:response_byte="S";8:response_byte=8'h30+{6'd0,source};
     9:response_byte=13;default:response_byte=10;
    endcase
    // CTRL P1 R0 BFF C80 VFF Q0\r\n, all values captured together.
    5: case(index)
     0,15:response_byte="C";1:response_byte="T";
     2,8:response_byte="R";3:response_byte="L";
     4,7,10,14,18,22:response_byte=" ";
     5:response_byte="P";6:response_byte=8'h31+{6'd0,active_picture};
     9:response_byte=active_auto ? "1" : "0";
     11:response_byte="B";12:response_byte=hex_char(active_brightness[7:4]);13:response_byte=hex_char(active_brightness[3:0]);
     16:response_byte=hex_char(active_contrast[7:4]);17:response_byte=hex_char(active_contrast[3:0]);
     19:response_byte="V";20:response_byte=hex_char(active_volume[7:4]);21:response_byte=hex_char(active_volume[3:0]);
     23:response_byte="Q";24:response_byte=active_busy ? "1" : "0";
     25:response_byte=13;default:response_byte=10;
    endcase
    default:response_byte=10;
   endcase
  end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   active<=0;waiting_done<=0;active_mode<=0;active_source<=0;active_id<=1;
   byte_index<=0;byte_count<=0;tx_start<=0;tx_data<=0;
   active_picture<=0;active_auto<=0;active_busy<=1;
   active_brightness<=255;active_contrast<=128;active_volume<=255;
  end else begin
   tx_start<=0;
   if(response_valid && response_ready)begin
    active<=1;active_id<=response_id;byte_index<=0;waiting_done<=0;
    active_mode<=emergency_active;active_source<=emergency_source;
    active_picture<=picture_index;active_auto<=autoplay;active_busy<=control_busy;
    active_brightness<=brightness;active_contrast<=contrast;active_volume<=volume;
    case(response_id)
     0,2:byte_count<=4;
     4:byte_count<=11;
     5:byte_count<=27;
     default:byte_count<=5;
    endcase
   end
   if(active && !waiting_done && !tx_busy)begin
    tx_data<=response_byte(active_id,byte_index,active_mode,active_source);
    tx_start<=1;waiting_done<=1;
   end else if(active && waiting_done && tx_done)begin
    waiting_done<=0;
    if(byte_index==byte_count-1'b1)begin active<=0;byte_index<=0;end
    else byte_index<=byte_index+1'b1;
   end
  end
 end
endmodule
