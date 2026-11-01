`timescale 1ns/1ps
// Separate CH340 channel. Reuse MiCu UART byte engines without altering them.
// CLK? CRLF -> MICU CLOCK 1 HH:MM:SS CRLF (or --:--:-- before calibration).
// TIME HH:MM:SS CRLF -> MICU TIME OK CRLF; malformed lines never set time.
module pc_time_uart #(
 parameter integer CLK_FREQ_HZ=25000000,
 parameter integer BAUD_RATE=115200,
 parameter integer GAP_CYCLES=CLK_FREQ_HZ/20
)(
 input wire clk,rst_n,rx,
 output wire tx,
 input wire clock_valid,
 input wire[23:0]clock_bcd,
 output reg set_valid,
 output reg[23:0]set_bcd
);
 wire[7:0]rx_data;
 wire rx_valid,framing_error,tick,tx_busy,tx_done;
 reg tx_start;
 reg[7:0]tx_data;
 uart_rx #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD_RATE(BAUD_RATE)) u_rx(
  .clk(clk),.rst_n(rst_n),.rx(rx),.data(rx_data),.valid(rx_valid),.framing_error(framing_error));
 baud_tick #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD_RATE(BAUD_RATE)) u_baud(.clk(clk),.rst_n(rst_n),.tick(tick));
 uart_tx u_tx(.clk(clk),.rst_n(rst_n),.tick(tick),.start(tx_start),.data(tx_data),
  .tx(tx),.busy(tx_busy),.done(tx_done));
 reg[127:0]line;
 reg[4:0]length;
 reg saw_cr,bad;
 localparam integer GW=GAP_CYCLES>1 ? $clog2(GAP_CYCLES) : 1;
 reg[GW-1:0]gap;
 reg active,waiting_done;
 reg[183:0]packet;
 reg[4:0]remaining;
 function digit;
  input[7:0]c;
  begin digit=c>="0" && c<="9";end
 endfunction
 wire digits_ok=digit(line[63:56]) && digit(line[55:48]) &&
  digit(line[39:32]) && digit(line[31:24]) && digit(line[15:8]) && digit(line[7:0]);
 wire[23:0]parsed={line[59:56],line[51:48],line[35:32],line[27:24],line[11:8],line[3:0]};
 wire time_ok=digits_ok && parsed[23:16]<=8'h23 && parsed[15:12]<=5 && parsed[7:4]<=5 &&
  line[47:40]==":" && line[23:16]==":";
 wire[63:0]time_ascii=clock_valid ?
  {4'h3,clock_bcd[23:20],4'h3,clock_bcd[19:16],8'h3a,
   4'h3,clock_bcd[15:12],4'h3,clock_bcd[11:8],8'h3a,
   4'h3,clock_bcd[7:4],4'h3,clock_bcd[3:0]} : "--:--:--";
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   line<=0;length<=0;saw_cr<=0;bad<=0;gap<=0;
   set_valid<=0;set_bcd<=0;active<=0;waiting_done<=0;packet<=0;remaining<=0;tx_start<=0;tx_data<=0;
  end else begin
   set_valid<=0;tx_start<=0;
   if(active && !waiting_done && !tx_busy)begin
    tx_data<=packet[183:176];tx_start<=1;waiting_done<=1;
   end else if(active && waiting_done && tx_done)begin
    waiting_done<=0;
    if(remaining==1)begin active<=0;remaining<=0;end
    else begin packet<={packet[175:0],8'd0};remaining<=remaining-1'b1;end
   end
   if(framing_error)begin bad<=1;gap<=0;end
   else if(rx_valid)begin
    gap<=0;
    if(rx_data==10)begin
     if(!active && (length!=0 || bad))begin
      active<=1;waiting_done<=0;
      if(!bad && saw_cr && length==4 && line[31:0]=="CLK?")begin
       packet<={"MICU CLOCK 1 ",time_ascii,8'd13,8'd10};remaining<=23;
      end else if(!bad && saw_cr && length==13 && line[103:64]=="TIME " && time_ok)begin
       set_bcd<=parsed;set_valid<=1;
       packet<={"MICU TIME OK",8'd13,8'd10,72'd0};remaining<=14;
      end else begin
       packet<={"MICU TIME ERR",8'd13,8'd10,64'd0};remaining<=15;
      end
     end
     line<=0;length<=0;saw_cr<=0;bad<=0;
    end else if(rx_data==13)begin
     if(saw_cr)bad<=1;
     saw_cr<=1;
    end else begin
     if(saw_cr || active)bad<=1;
     if(length<16)begin line<={line[119:0],rx_data};length<=length+1'b1;end
     else bad<=1;
    end
   end else if(length!=0 || saw_cr || bad)begin
    if(gap==GAP_CYCLES-1)begin bad<=1;gap<=gap;end
    else gap<=gap+1'b1;
   end
  end
 end
endmodule
