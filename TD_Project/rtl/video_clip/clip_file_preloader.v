`timescale 1ns/1ps
// Optional XAV1 file -> unused SDRAM region. The validated sector engine and
// write CDC are shared with the existing player; no SD protocol changes.
module clip_file_preloader #(
 parameter integer FRAME_WORDS=19200, FRAMES=20, WIDTH=160, HEIGHT=120, FPS=10,
 parameter integer VOICE_SAMPLES=16000,VOICE_RATE=8000,
 parameter integer EXTERNAL_FILE=0,
 parameter [20:0] BASE_WORD=21'd1228800
)(
 input wire clk,rst_n,start,
 input wire[31:0]first_cluster,file_size,fat_start,data_start,max_cluster,
 input wire[7:0]spc,
 output wire sector_req,output wire[31:0]sector_lba,
 input wire sector_busy,sector_valid,sector_done,
 input wire[7:0]sector_byte,sector_error,input wire[8:0]sector_index,
 input wire write_full,output reg write_en,output reg[20:0]write_addr,
 output reg[31:0]write_data,
 output reg voice_write_en,output reg[13:0]voice_write_addr,output reg[7:0]voice_write_data,
 output wire external_start,input wire external_valid,external_done,
 input wire[7:0]external_byte,external_error,input wire[31:0]external_offset,
 output reg done,output reg[7:0]error
);
 localparam integer PAYLOAD_BYTES=FRAME_WORDS*FRAMES*4;
 reg file_start,active,header_bad,payload_bad;
 reg[23:0]packed_rgb;
 reg[15:0]crc,expected_crc;
 wire file_valid,file_done;wire[7:0]file_byte,file_error;wire[31:0]offset;
 function[15:0]crc_byte;
  input[15:0]old_crc;input[7:0]value;reg[15:0]v;integer k;
  begin v=old_crc^{value,8'd0};for(k=0;k<8;k=k+1)v=v[15] ? (v<<1)^16'h1021 : v<<1;crc_byte=v;end
 endfunction
 function[7:0]header_value;
  input[4:0]i;
  begin case(i)
   0:header_value="X";1:header_value="A";2:header_value="V";3:header_value="1";
   4:header_value=WIDTH&255;5:header_value=WIDTH>>8;
   6:header_value=HEIGHT&255;7:header_value=HEIGHT>>8;
   8:header_value=FRAMES&255;9:header_value=FRAMES>>8;
   10:header_value=FPS&255;11:header_value=FPS>>8;
   12:header_value=4;13,14,15:header_value=0;
   16:header_value=PAYLOAD_BYTES&255;17:header_value=(PAYLOAD_BYTES>>8)&255;
   18:header_value=(PAYLOAD_BYTES>>16)&255;19:header_value=(PAYLOAD_BYTES>>24)&255;
   22:header_value=VOICE_SAMPLES==0 ? 0 : VOICE_RATE&255;
   23:header_value=VOICE_SAMPLES==0 ? 0 : VOICE_RATE>>8;
   24:header_value=VOICE_SAMPLES&255;25:header_value=(VOICE_SAMPLES>>8)&255;
   26:header_value=(VOICE_SAMPLES>>16)&255;27:header_value=(VOICE_SAMPLES>>24)&255;
   28:header_value=VOICE_SAMPLES==0 ? 0 : 8;29:header_value=VOICE_SAMPLES==0 ? 0 : 1;
   default:header_value=0;
  endcase end
 endfunction
 assign external_start=file_start;
 generate if(EXTERNAL_FILE)begin:g_external
  assign file_valid=external_valid;assign file_done=external_done;
  assign file_byte=external_byte;assign file_error=external_error;assign offset=external_offset;
  assign sector_req=0;assign sector_lba=0;
 end else begin:g_local
 fat32_file_streamer u_file(
  .clk(clk),.rst_n(rst_n),.file_start(file_start),.first_cluster(first_cluster),.file_size(file_size),
  .sectors_per_cluster(spc),.fat_start_lba(fat_start),.data_start_lba(data_start),.max_cluster(max_cluster),
  .file_busy(),.file_done(file_done),.file_valid(file_valid),.file_byte(file_byte),
  .file_byte_offset(offset),.fs_error(file_error),.sector_req(sector_req),.sector_lba(sector_lba),
  .sector_busy(sector_busy),.sector_valid(sector_valid),.sector_byte(sector_byte),
  .sector_byte_index(sector_index),.sector_done(sector_done),.sector_error(sector_error));
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   file_start<=0;active<=0;done<=0;error<=0;header_bad<=0;payload_bad<=0;
   packed_rgb<=0;crc<=16'hffff;expected_crc<=0;write_en<=0;write_addr<=BASE_WORD;write_data<=0;
   voice_write_en<=0;voice_write_addr<=0;voice_write_data<=0;
  end else begin
   file_start<=0;done<=0;write_en<=0;voice_write_en<=0;
   if(start && !active)begin
    header_bad<=0;payload_bad<=0;crc<=16'hffff;expected_crc<=0;error<=0;
    if(file_size!=PAYLOAD_BYTES+VOICE_SAMPLES+512)begin done<=1;error<=8'hd1;end
    else begin active<=1;file_start<=1;end
   end
   if(active && file_valid)begin
    if((offset<20 || (offset>=22 && offset<30)) && file_byte!=header_value(offset[4:0]))header_bad<=1;
    if(offset==20)expected_crc[7:0]<=file_byte;
    if(offset==21)expected_crc[15:8]<=file_byte;
    if(offset>=512)crc<=crc_byte(crc,file_byte);
    if(offset>=512 && offset<PAYLOAD_BYTES+512)begin
     case(offset[1:0])
      0:packed_rgb[7:0]<=file_byte;
      1:packed_rgb[15:8]<=file_byte;
      2:packed_rgb[23:16]<=file_byte;
      3:begin
       if(file_byte!=0 || write_full)payload_bad<=1;
       if(!header_bad && !payload_bad && file_byte==0 && !write_full)begin
        write_en<=1;write_addr<=BASE_WORD+((offset-512)>>2);write_data<={8'd0,packed_rgb};
       end
      end
     endcase
    end
    if(VOICE_SAMPLES!=0 && offset>=PAYLOAD_BYTES+512 && !header_bad && !payload_bad)begin
     voice_write_en<=1;voice_write_addr<=offset-PAYLOAD_BYTES-512;voice_write_data<=file_byte;
    end
   end
   if(active && file_done)begin
    active<=0;done<=1;
    if(file_error!=0)error<=8'hd2;
    else if(header_bad)error<=8'hd3;
    else if(payload_bad)error<=8'hd4;
    else if(crc!=expected_crc)error<=8'hd5;
   end
  end
 end
endmodule
