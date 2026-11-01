`timescale 1ns/1ps
// Shared directory scan / sector adapter, two independent FAT cursors/rings.
// Sector ownership is held until done; round-robin also covers FAT lookups.
module dual_fat32_pcm_source #(parameter integer SD_TIMEOUT_CYCLES=50000000,ENABLE_CLIP=0)(
 input wire clk,rst_n,enable,
 output wire sd_read,output wire[31:0]sd_lba,
 input wire sd_valid,input wire[7:0]sd_byte,input wire sd_end,
 input wire pix_clk,pix_rst_n,sample_tick,normal_ready,alert_ready,
 output wire normal_valid,alert_valid,normal_active,alert_active,
 output wire signed[15:0]normal_sample,alert_sample,
 output wire[7:0]error,
 input wire clip_write_full,clip_write_idle,
 output wire clip_write_en,output wire[20:0]clip_write_addr,output wire[31:0]clip_write_data,
 output reg clip_write_reset,clip_init_done,clip_ready,output reg[7:0]clip_error
 ,output wire clip_voice_write_en,output wire[13:0]clip_voice_write_addr,output wire[7:0]clip_voice_write_data
);
 reg[2:0]state; // 0 wait, 1 scan, 2 audio, 3 clip preload, 4 write drain, 5 failed
 reg clip_start;reg[10:0]clip_settle;
 wire clip_req,clip_done;wire[31:0]clip_lba;wire[7:0]clip_load_error;
 wire clip_file_start,clip_file_valid,clip_file_done;wire[7:0]clip_file_byte,clip_file_error;wire[31:0]clip_file_offset;
 wire[31:0]clip_cluster,clip_size;
 reg scan_start,start0,start1;
 reg[7:0]scan_status;
 wire scan_done,scan_req;wire[7:0]scan_error;wire[31:0]scan_lba;
 wire[31:0]cluster0,cluster1,size0,size1,fat_start,data_start,max_cluster;
 wire[7:0]spc;wire[3:0]resources;
 wire req0,req1;wire[31:0]lba0,lba1;wire[7:0]error0,error1;
 wire under0,under1;reg[1:0]under0_sync,under1_sync;
 wire busy,valid,done;wire[7:0]data,sector_error;wire[8:0]index;
 reg owner,turn;
 wire request=state==1 ? scan_req : state==3 ? req0 : (state==2 && (req0 || req1));
 wire[31:0]address=state==1 ? scan_lba : state==3 ? lba0 : (req1 ? lba1 : lba0);
 // Request is registered in the clients. Block the other client during that
 // cycle before adapter busy asserts; otherwise a pulse could be lost.
 wire blocked=busy || req0 || req1 || state!=2;
 sd_sector_adapter #(.TIMEOUT_CYCLES(SD_TIMEOUT_CYCLES)) u_sector(
  .clk(clk),.rst(!rst_n),.enable(enable),.sector_req(request),.sector_lba(address),
  .sector_busy(busy),.sector_valid(valid),.sector_byte(data),.sector_byte_index(index),
  .sector_done(done),.sector_error(sector_error),.sd_sec_read(sd_read),.sd_sec_read_addr(sd_lba),
  .sd_sec_read_data_valid(sd_valid),.sd_sec_read_data(sd_byte),.sd_sec_read_end(sd_end));
 fat32_volume_scanner #(.AUDIO_ONLY(1),.DUAL_AUDIO(1),.ENABLE_CLIP(ENABLE_CLIP)) u_scan(
  .clk(clk),.rst_n(rst_n),.scan_start(scan_start),.scan_busy(),.scan_done(scan_done),.fs_error(scan_error),
  .partition_lba(),.sectors_per_cluster(spc),.fat_start_lba(fat_start),.data_start_lba(data_start),.max_cluster(max_cluster),
  .resource_valid(resources),.resource0_cluster(cluster0),.resource1_cluster(cluster1),
  .resource2_cluster(clip_cluster),.resource3_cluster(),.resource0_size(size0),.resource1_size(size1),.resource2_size(clip_size),.resource3_size(),
  .sector_req(scan_req),.sector_lba(scan_lba),.sector_busy(busy),.sector_valid(valid && state==1),
  .sector_byte(data),.sector_byte_index(index),.sector_done(done && state==1),.sector_error(sector_error));
 generate if(ENABLE_CLIP)begin:g_clip
 clip_file_preloader #(.EXTERNAL_FILE(1)) u_clip(
  .clk(clk),.rst_n(rst_n),.start(clip_start),.first_cluster(clip_cluster),.file_size(clip_size),
  .fat_start(fat_start),.data_start(data_start),.max_cluster(max_cluster),.spc(spc),
  .sector_req(clip_req),.sector_lba(clip_lba),.sector_busy(busy || state!=3),
  .sector_valid(valid && state==3),.sector_done(done && state==3),
  .sector_byte(data),.sector_error(sector_error),.sector_index(index),
  .write_full(clip_write_full),.write_en(clip_write_en),.write_addr(clip_write_addr),.write_data(clip_write_data),
  .voice_write_en(clip_voice_write_en),.voice_write_addr(clip_voice_write_addr),.voice_write_data(clip_voice_write_data),
  .external_start(clip_file_start),.external_valid(clip_file_valid),.external_done(clip_file_done),
  .external_byte(clip_file_byte),.external_error(clip_file_error),.external_offset(clip_file_offset),
  .done(clip_done),.error(clip_load_error));
 end else begin:g_no_clip
  assign clip_req=0;assign clip_lba=0;assign clip_done=0;assign clip_load_error=0;
  assign clip_write_en=0;assign clip_write_addr=0;assign clip_write_data=0;
  assign clip_voice_write_en=0;assign clip_voice_write_addr=0;assign clip_voice_write_data=0;
  assign clip_file_start=0;
 end endgenerate
 fat32_loop_stream #(.SHARE_CLIP(ENABLE_CLIP)) u_normal(
  .clk(clk),.rst_n(rst_n),.start(start0),.first_cluster(cluster0),.file_size(size0),
  .fat_start(fat_start),.data_start(data_start),.max_cluster(max_cluster),.spc(spc),
  .sector_req(req0),.sector_lba(lba0),.sector_busy(state==3 ? busy : (blocked || turn)),
  .sector_valid(valid && ((state==2 && !owner) || state==3)),.sector_done(done && ((state==2 && !owner) || state==3)),
  .sector_byte(data),.sector_index(index),.sector_error(sector_error),
  .pix_clk(pix_clk),.pix_rst_n(pix_rst_n),.sample_tick(sample_tick),.sample_ready(normal_ready),
  .sample_valid(normal_valid),.sample_out(normal_sample),.active(normal_active),.error(error0),.sample_counter(),.underrun(under0),
  .clip_phase(state==3),.clip_start(clip_file_start),.clip_cluster(clip_cluster),.clip_size(clip_size),
  .clip_file_valid(clip_file_valid),.clip_file_done(clip_file_done),.clip_file_byte(clip_file_byte),
  .clip_file_error(clip_file_error),.clip_file_offset(clip_file_offset));
 fat32_loop_stream u_alert(
  .clk(clk),.rst_n(rst_n),.start(start1),.first_cluster(cluster1),.file_size(size1),
  .fat_start(fat_start),.data_start(data_start),.max_cluster(max_cluster),.spc(spc),
  .sector_req(req1),.sector_lba(lba1),.sector_busy(blocked || !turn),
  .sector_valid(valid && state==2 && owner),.sector_done(done && state==2 && owner),
  .sector_byte(data),.sector_index(index),.sector_error(sector_error),
  .pix_clk(pix_clk),.pix_rst_n(pix_rst_n),.sample_tick(sample_tick),.sample_ready(alert_ready),
  .sample_valid(alert_valid),.sample_out(alert_sample),.active(alert_active),.error(error1),.sample_counter(),.underrun(under1));
 assign error=scan_status!=0 ? scan_status : error0!=0 ? 8'hb2 : error1!=0 ? 8'hb5 :
              under0_sync[1] ? 8'hb7 : under1_sync[1] ? 8'hb8 : 0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin under0_sync<=0;under1_sync<=0;end
  else begin under0_sync<={under0_sync[0],under0};under1_sync<={under1_sync[0],under1};end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;scan_start<=0;start0<=0;start1<=0;scan_status<=0;owner<=0;turn<=0;
   clip_start<=0;clip_settle<=0;clip_write_reset<=0;clip_init_done<=0;clip_ready<=0;clip_error<=0;end
  else begin
   scan_start<=0;start0<=0;start1<=0;clip_start<=0;
   if(state==2 && !busy)begin
    if(req0 || req1)begin owner<=req1;turn<=!req1;end
    else turn<=!turn;
   end
   case(state)
    0:if(enable)begin scan_start<=1;state<=1;end
    1:if(scan_done)begin
     if(scan_error!=0 && scan_error!=8'h22)begin scan_status<=8'hb6;state<=5;clip_init_done<=1;end
     else begin
      if(ENABLE_CLIP && resources[2])begin state<=3;clip_start<=1;end
      else begin
       state<=2;clip_init_done<=1;
       start0<=resources[0] && size0!=0 && size0[8:0]==0;
       start1<=resources[1] && size1!=0 && size1[8:0]==0;
      end
      if(!resources[0])scan_status<=8'hb0;
      else if(size0==0 || size0[8:0]!=0)scan_status<=8'hb1;
      else if(!resources[1])scan_status<=8'hb3;
      else if(size1==0 || size1[8:0]!=0)scan_status<=8'hb4;
     end
    end
    3:if(clip_done)begin
     state<=4;clip_settle<=0;clip_error<=clip_load_error;
     if(clip_load_error!=0)clip_write_reset<=1;
    end
    4:begin
     if(!clip_write_idle)clip_settle<=0;
     else if(clip_settle==1023)begin
      clip_write_reset<=0;clip_ready<=clip_error==0;clip_init_done<=1;state<=2;
      start0<=resources[0] && size0!=0 && size0[8:0]==0;
      start1<=resources[1] && size1!=0 && size1[8:0]==0;
     end else clip_settle<=clip_settle+1'b1;
    end
    default:;
   endcase
  end
 end
endmodule
