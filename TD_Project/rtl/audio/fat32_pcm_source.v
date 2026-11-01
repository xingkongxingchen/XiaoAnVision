`timescale 1ns/1ps
// MiCu lesson 11: ordinary FAT32 AUDIO.PCM -> sector-sized credits -> WAV ring.
// No raw-card writes, contiguous-allocation assumption or SDRAM audio traffic.
module fat32_pcm_source #(
 parameter integer SD_TIMEOUT_CYCLES=50000000
)(
 input wire clk,rst_n,enable,
 output wire sd_read,output wire[31:0]sd_lba,
 input wire sd_valid,input wire[7:0]sd_byte,input wire sd_end,
 input wire pix_clk,pix_rst_n,sample_tick,sample_ready,
 output wire sample_valid,output wire signed[15:0]sample_out,
 output wire stream_active,stream_end,output wire[31:0]sample_counter,
 output reg[7:0]error,output reg[2:0]state
);
 localparam WAIT=0,SCAN=1,START=2,PLAY=3,FINISH=4,ABSENT=5,FAILED=6;
 reg scan_start,file_start,play_enable,credit,last_bytes;
 reg virtual_done;
 wire scan_done,scan_busy;wire[7:0]scan_error;
 wire[31:0]first_cluster,file_size,fat_start,data_start,max_cluster;
 wire[7:0]spc;wire[3:0]resources;
 wire scan_req,file_req,sector_busy,sector_valid,sector_done;
 wire[31:0]scan_lba,file_lba;
 wire[7:0]sector_byte,sector_error;wire[8:0]sector_index;
 wire file_valid,file_done;wire[7:0]file_byte,file_error;wire[31:0]file_offset;
 wire wav_req;wire[31:0]wav_lba;
 wire wav_busy=credit || !play_enable;
 sd_sector_adapter #(.TIMEOUT_CYCLES(SD_TIMEOUT_CYCLES)) u_sector(
  .clk(clk),.rst(!rst_n),.enable(enable),
  .sector_req(state==SCAN ? scan_req : file_req),.sector_lba(state==SCAN ? scan_lba : file_lba),
  .sector_busy(sector_busy),.sector_valid(sector_valid),.sector_byte(sector_byte),
  .sector_byte_index(sector_index),.sector_done(sector_done),.sector_error(sector_error),
  .sd_sec_read(sd_read),.sd_sec_read_addr(sd_lba),.sd_sec_read_data_valid(sd_valid),
  .sd_sec_read_data(sd_byte),.sd_sec_read_end(sd_end));
 fat32_volume_scanner #(.AUDIO_ONLY(1)) u_scan(
  .clk(clk),.rst_n(rst_n),.scan_start(scan_start),.scan_busy(scan_busy),.scan_done(scan_done),
  .fs_error(scan_error),.partition_lba(),.sectors_per_cluster(spc),.fat_start_lba(fat_start),
  .data_start_lba(data_start),.max_cluster(max_cluster),.resource_valid(resources),
  .resource0_cluster(first_cluster),.resource0_size(file_size),
  .resource1_cluster(),.resource2_cluster(),.resource3_cluster(),
  .resource1_size(),.resource2_size(),.resource3_size(),
  .sector_req(scan_req),.sector_lba(scan_lba),.sector_busy(sector_busy),
  .sector_valid(sector_valid && state==SCAN),.sector_byte(sector_byte),.sector_byte_index(sector_index),
  .sector_done(sector_done && state==SCAN),.sector_error(sector_error));
 fat32_file_streamer u_file(
  .clk(clk),.rst_n(rst_n),.file_start(file_start),.first_cluster(first_cluster),.file_size(file_size),
  .sectors_per_cluster(spc),.fat_start_lba(fat_start),.data_start_lba(data_start),.max_cluster(max_cluster),
  .file_busy(),.file_done(file_done),.file_valid(file_valid),.file_byte(file_byte),
  .file_byte_offset(file_offset),.fs_error(file_error),.sector_req(file_req),.sector_lba(file_lba),
  // A full 512-byte ring-buffer credit admits one file sector. FAT chain reads
  // don't spend credits. Permit final EOF-chain validation after final bytes.
  .sector_busy(sector_busy || (!credit && !last_bytes)),
  .sector_valid(sector_valid && state==PLAY),.sector_byte(sector_byte),.sector_byte_index(sector_index),
  .sector_done(sector_done && state==PLAY),.sector_error(sector_error));
 wav_stream_player u_wav(
  .wr_clk(clk),.wr_rst_n(rst_n),.play_enable(play_enable),
  .start_lba(32'd1),.total_sectors(file_size >> 9), // logical PCM sectors, FAT maps physical LBA
  .sd_req(wav_req),.sd_lba(wav_lba),.sd_busy(wav_busy),
  .sd_valid(file_valid),.sd_byte(file_byte),.sd_byte_index(file_offset[8:0]),
  .sd_done(virtual_done || (file_done && file_error!=0)),.sd_error(file_error),
  .rd_clk(pix_clk),.rd_rst_n(pix_rst_n),.sample_tick(sample_tick),.sample_out(sample_out),
  .sample_valid(sample_valid),.sample_ready(sample_ready),.sample_counter(sample_counter),
  .stream_active(stream_active),.stream_end(stream_end),.buffer_low());
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=WAIT;error<=0;scan_start<=0;file_start<=0;play_enable<=0;
   credit<=0;last_bytes<=0;virtual_done<=0;
  end else begin
   scan_start<=0;file_start<=0;virtual_done<=0;
   if(wav_req && !wav_busy)credit<=1;
   if(file_valid && file_offset[8:0]==511)begin
    credit<=0;virtual_done<=1;
    if(file_offset==file_size-1)last_bytes<=1;
   end
   case(state)
    WAIT:if(enable)begin scan_start<=1;state<=SCAN;end
    SCAN:if(scan_done)begin
     if(scan_error==8'h22)state<=ABSENT; // no AUDIO.PCM: keep the verified melody
     else if(scan_error!=0)begin error<=scan_error;state<=FAILED;end
     else if(file_size==0 || file_size[8:0]!=0)begin error<=8'h91;state<=FAILED;end
     else state<=START;
    end
    START:begin play_enable<=1;file_start<=1;state<=PLAY;end
    PLAY:if(file_done)begin
     if(file_error!=0)begin error<=file_error;state<=FAILED;end
     else state<=FINISH;
    end
    default:;
   endcase
  end
 end
endmodule
