`timescale 1ns/1ps
// One file cursor + MiCu BRAM ring. Successful EOF restarts the FAT cursor,
// not the ring: the last sample and next first sample remain in order.
module fat32_loop_stream #(parameter integer SHARE_CLIP=0)(
 input wire clk,rst_n,start,
 input wire[31:0]first_cluster,file_size,fat_start,data_start,max_cluster,
 input wire[7:0]spc,
 output wire sector_req,output wire[31:0]sector_lba,
 input wire sector_busy,sector_valid,sector_done,
 input wire[7:0]sector_byte,sector_error,input wire[8:0]sector_index,
 input wire pix_clk,pix_rst_n,sample_tick,sample_ready,
 output wire sample_valid,output wire signed[15:0]sample_out,
 output wire active,output reg[7:0]error,output wire underrun,
 output wire[31:0]sample_counter
 ,input wire clip_phase,clip_start,input wire[31:0]clip_cluster,clip_size,
 output wire clip_file_valid,clip_file_done,output wire[7:0]clip_file_byte,clip_file_error,
 output wire[31:0]clip_file_offset
);
 reg started,file_start,credit,last_bytes,virtual_done;
 reg credit_pending;
 reg[31:0]last_file_offset;
 wire file_valid,file_done;wire[7:0]file_byte,file_error;wire[31:0]file_offset;
 wire preload=SHARE_CLIP && clip_phase;
 assign clip_file_valid=file_valid;assign clip_file_done=file_done;
 assign clip_file_byte=file_byte;assign clip_file_error=file_error;assign clip_file_offset=file_offset;
 wire wav_req;wire wav_busy=!started || credit || error!=0;
 fat32_file_streamer u_file(
  .clk(clk),.rst_n(rst_n),.file_start(preload ? clip_start : file_start),
  .first_cluster(preload ? clip_cluster : first_cluster),.file_size(preload ? clip_size : file_size),
  .sectors_per_cluster(spc),.fat_start_lba(fat_start),.data_start_lba(data_start),.max_cluster(max_cluster),
  .file_busy(),.file_done(file_done),.file_valid(file_valid),.file_byte(file_byte),
  .file_byte_offset(file_offset),.fs_error(file_error),.sector_req(sector_req),.sector_lba(sector_lba),
  .sector_busy(sector_busy || (!preload && !credit && !last_bytes)),.sector_valid(sector_valid),
  .sector_byte(sector_byte),.sector_byte_index(sector_index),.sector_done(sector_done),.sector_error(sector_error));
 wav_stream_player #(.LOOP(1)) u_wav(
  .wr_clk(clk),.wr_rst_n(rst_n),.play_enable(started),.start_lba(32'd1),.total_sectors(file_size>>9),
  .sd_req(wav_req),.sd_lba(),.sd_busy(wav_busy),.sd_valid(file_valid && !preload),.sd_byte(file_byte),
  .sd_byte_index(file_offset[8:0]),.sd_done(virtual_done || (file_done && file_error!=0)),.sd_error(file_error),
  .rd_clk(pix_clk),.rd_rst_n(pix_rst_n),.sample_tick(sample_tick),.sample_ready(sample_ready),
  .sample_valid(sample_valid),.sample_out(sample_out),.sample_counter(sample_counter),
  .stream_active(active),.stream_end(),.buffer_low(),.underrun(underrun));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin started<=0;file_start<=0;credit<=0;last_bytes<=0;virtual_done<=0;error<=0;credit_pending<=0;last_file_offset<=0;end
  else begin
   file_start<=0;virtual_done<=0;
   last_file_offset<=file_size-1;
   // Reserve ring capacity before releasing the corresponding FAT request.
   credit_pending<=!preload && wav_req && !wav_busy;
   if(start && !started)begin started<=1;file_start<=1;end
   if(credit_pending)credit<=1;
   if(!preload && file_valid && file_offset[8:0]==511)begin
    credit<=0;virtual_done<=1;
    if(file_offset==last_file_offset)last_bytes<=1;
   end
   if(!preload && file_done)begin
    if(file_error!=0)error<=file_error;
    else begin file_start<=1;last_bytes<=0;end
   end
  end
 end
endmodule
