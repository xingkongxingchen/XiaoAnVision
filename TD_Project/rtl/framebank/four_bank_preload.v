`timescale 1ns/1ps
// Lecture 7 file frontend -> lecture 8 resident-bank loader/write CDC.
// No SD traffic after all four banks have been committed. Read side starts only
// after all writes drain, avoiding concurrent read/write arbitration changes.
module four_bank_preload #(
 parameter integer WIDTH=640, HEIGHT=480, CLK_FREQ_HZ=100000000,
 parameter integer SD_TIMEOUT_MS=500, ENABLE_AUDIO=0, ENABLE_SCALE=0,
 parameter integer ENABLE_CRC_DIAG=0, ENABLE_CLIP=0
)(
 input wire clk,rst_n,mem_clk,mem_rst_n,controller_busy,
 output wire sd_ncs,sd_dclk,sd_mosi,input wire sd_miso,
 output wire app_wr_en,output wire[20:0]app_wr_addr,
 output wire[31:0]app_wr_data,output wire[3:0]app_wr_mask,
 output reg[3:0]complete,output wire ready,
 output wire[2:0]found,output reg[1:0]load_index,
 output reg[3:0]state,output reg[7:0]error,
 output wire[31:0]file_len,pixel_offset,
 output wire[31:0]timeout_trace,timeout_lba,
 output reg[31:0]boot_trace,boot_command,
 input wire audio_sd_req,input wire[31:0]audio_sd_lba,
 output wire audio_sd_ready,audio_sd_valid,audio_sd_end,output wire[7:0]audio_sd_byte,
 input wire clip_write_en,clip_write_reset,input wire[20:0]clip_write_addr,input wire[31:0]clip_write_data,
 output wire clip_write_full,clip_write_idle,
 output wire[3:0]diag_checked,output wire diag_fault,diag_protocol_fault,
 output wire[1:0]diag_index,output wire[31:0]diag_actual,diag_expected
);
 localparam BOOT=0,SCAN=1,CLEAR=2,START=3,HEADER=4,ACK=5,
            STREAM=6,DRAIN=7,NEXT=8,DONE=9,RECOVER=10,HALT=15;
 reg scan_start,load_start,writer_start,write_ack;
 reg writer_reset,source_done,writer_done,retried;
 reg ready_latched;
 reg[31:0]timer;
 reg[10:0]settle;
 wire sd_init,sd_recover,parser_ready,scan_done,parse_done,parse_error,write_req;
 wire[31:0]sd_debug_command;
 wire[7:0]sd_debug_status;
 wire[3:0]parse_code,parse_state;
 wire sec_req,sec_valid,sec_end;
 wire[31:0]sec_addr;
 wire[7:0]sec_data;
 wire pixel_valid;
 wire bmp_top_down;
 wire[23:0]pixel_rgb;
 wire writer_busy,writer_finish,src_wr,src_full,src_overflow,dst_idle;
 wire[7:0]writer_error;
 wire[20:0]src_addr;
 wire[31:0]src_data;
 wire[3:0]src_mask;
 wire write_rst_n=rst_n && !writer_reset && !(ENABLE_CLIP && clip_write_reset);
 assign clip_write_full=src_full;
 wire dst_rst_n;
 reset_sync u_write_reset(.clk(mem_clk),.ext_rst_n(mem_rst_n && write_rst_n),.rst_n_sync(dst_rst_n));
 wire idle_sync,busy_sync;
 assign clip_write_idle=idle_sync && !busy_sync;
 sync_2ff u_idle(.clk(clk),.rst_n(rst_n),.async_in(dst_idle),.sync_out(idle_sync));
 sync_2ff u_busy(.clk(clk),.rst_n(rst_n),.async_in(controller_busy),.sync_out(busy_sync));
 assign ready=ready_latched;
 // One-way ownership handoff only after all four picture writes have drained.
 // Keep the validated SD SPI engine and its held-request protocol unchanged.
 wire audio_owner=(ENABLE_AUDIO!=0) && ready;
 assign audio_sd_ready=audio_owner && sd_init;
 assign audio_sd_valid=audio_owner && sec_valid;
 assign audio_sd_end=audio_owner && sec_end;
 assign audio_sd_byte=sec_data;
 // Existing driver parameter only: 100 MHz / ((2+2)*2) = 12.5 MHz.
 // Preserve initialization rate and the validated held-request protocol.
 sd_card_top #(.SPI_HIGH_SPEED_DIV(2)) u_sd(.clk(clk),.rst(!rst_n || sd_recover),
  .debug_command(sd_debug_command),.debug_status(sd_debug_status),
  .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso),
  .sd_init_done(sd_init),.sd_sec_read(audio_owner ? audio_sd_req : sec_req),
  .sd_sec_read_addr(audio_owner ? audio_sd_lba : sec_addr),
  .sd_sec_read_data(sec_data),.sd_sec_read_data_valid(sec_valid),.sd_sec_read_end(sec_end),
  .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),
  .sd_sec_write_data_req(),.sd_sec_write_end());
 fat32_bmp_read #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.SD_READ_TIMEOUT_MS(SD_TIMEOUT_MS),.ENABLE_SCALE(ENABLE_SCALE)) u_parser(
  .clk(clk),.rst(!rst_n),.ready(parser_ready),.load_done(parse_done),
  .load_error(parse_error),.error_code(parse_code),.sd_recover_reset(sd_recover),
  .header_file_len(file_len),.header_pixel_offset(pixel_offset),
  .timeout_trace(timeout_trace),.timeout_lba(timeout_lba),
  .scan_start(scan_start),.scan_done(scan_done),.scan_found_valid(),
  .scan_found_sector(),.scan_found_total(found),.load_start(load_start),
  .load_sector({30'd0,load_index}),.sd_init_done(sd_init),.state_code(parse_state),
  .bmp_width(WIDTH[15:0]),.bmp_height(HEIGHT[15:0]),
  .write_req(write_req),.write_req_ack(write_ack),
  .sd_sec_read(sec_req),.sd_sec_read_addr(sec_addr),.sd_sec_read_data(sec_data),
  .sd_sec_read_data_valid(sec_valid),.sd_sec_read_end(sec_end),
  .bmp_data_wr_en(pixel_valid),.bmp_data(pixel_rgb),.bmp_top_down(bmp_top_down));
 generate if(ENABLE_CRC_DIAG)begin:g_crc
  pixel_crc_probe #(.IMAGE_WORDS(WIDTH*HEIGHT),.SERIAL(1),
   .EXPECT0(32'h00005941),.EXPECT1(32'h00001f85),.EXPECT2(32'h0000d8ec),.EXPECT3(32'h00004d0c)) u_probe(
   .clk(clk),.rst_n(rst_n),.start(writer_start),.image_index(load_index),
   .data_valid(pixel_valid && state==STREAM),.pixel_rgb(pixel_rgb),
   .checked(diag_checked),.bad(),.fault(diag_fault),.protocol_fault(diag_protocol_fault),
   .fault_index(diag_index),.fault_actual(diag_actual),.fault_expected(diag_expected));
 end else begin:g_no_crc
  assign diag_checked=0;assign diag_fault=0;assign diag_protocol_fault=0;
  assign diag_index=0;assign diag_actual=0;assign diag_expected=0;
 end endgenerate
 media_frame_loader #(.IMAGE_WORDS(WIDTH*HEIGHT),.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT),.DYNAMIC_ORIENTATION(ENABLE_SCALE)) u_loader(
  .bmp_top_down(bmp_top_down),
  .clk(clk),.rst_n(write_rst_n),.load_start(writer_start),.image_index(load_index),
  .pixel_valid(pixel_valid && state==STREAM),.pixel_rgb(pixel_rgb),.frame_commit(parse_done),
  .decode_error(parse_error ? 8'h01 : 8'h00),.load_busy(writer_busy),.load_done(writer_finish),
  .image_complete(),.memory_error(writer_error),.controller_init_done(1'b1),
  .controller_busy(1'b0),.refresh_active(1'b0),.app_wr_en(src_wr),.app_wr_addr(src_addr),
  .app_wr_mask(src_mask),.app_wr_data(src_data));
 media_sdram_write_cdc u_write_cdc(
  .src_clk(clk),.src_rst_n(write_rst_n),
  .src_wr_en((ENABLE_CLIP && ready) ? clip_write_en : src_wr),
  .src_wr_addr((ENABLE_CLIP && ready) ? clip_write_addr : src_addr),
  .src_wr_mask((ENABLE_CLIP && ready) ? 4'd0 : src_mask),
  .src_wr_data((ENABLE_CLIP && ready) ? clip_write_data : src_data),.src_full(src_full),.src_overflow(src_overflow),
  .dst_clk(mem_clk),.dst_rst_n(dst_rst_n),.dst_app_wr_en(app_wr_en),.dst_app_wr_addr(app_wr_addr),
  .dst_app_wr_mask(app_wr_mask),.dst_app_wr_data(app_wr_data),.dst_idle(dst_idle));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   state<=BOOT;complete<=0;load_index<=0;error<=0;timer<=0;settle<=0;
   ready_latched<=0;
   boot_trace<=0;boot_command<=0;
   scan_start<=0;load_start<=0;writer_start<=0;write_ack<=0;writer_reset<=1;
   source_done<=0;writer_done<=0;retried<=0;
  end else begin
   scan_start<=0;load_start<=0;writer_start<=0;
   if(parse_done)source_done<=1;
   if(writer_finish)writer_done<=1;
   if(state!=DONE && state!=HALT)timer<=timer+1'b1;
   if(state!=DONE && state!=HALT && timer>=CLK_FREQ_HZ*30-1)begin
    error<=8'h70;state<=HALT;write_ack<=0;
    // Freeze PRE-halt state; subsequent command retries cannot overwrite it.
    boot_trace<={8'hd7,state,parse_state,sd_init,parser_ready,scan_done,write_req,
                 writer_busy,idle_sync,busy_sync,audio_owner,sd_debug_status};
    boot_command<=sd_debug_command;
   end else if((state==HEADER || state==ACK || state==STREAM || state==DRAIN) && parse_error)begin
    write_ack<=0;settle<=0;
    if(!retried && parse_code==6)begin retried<=1;state<=RECOVER;end
    else begin error<={4'h1,parse_code};state<=HALT;end
   end else if((state==STREAM || state==DRAIN) && (writer_error!=0 || src_overflow))begin
    error<=src_overflow ? 8'h47 : writer_error;state<=HALT;
   end else case(state)
    BOOT:if(parser_ready)begin scan_start<=1;state<=SCAN;timer<=0;end
    SCAN:if(parse_error || parse_state==4'he)begin error<={4'h1,parse_code};state<=HALT;end
      else if(scan_done && parser_ready)begin
       if(found==4)begin state<=CLEAR;settle<=0;end
       else begin error<=8'h71;state<=HALT;end
      end
    CLEAR:begin
     writer_reset<=1;source_done<=0;writer_done<=0;write_ack<=0;
     if(settle==1023)begin writer_reset<=0;state<=START;settle<=0;end
     else settle<=settle+1'b1;
    end
    START:if(parser_ready)begin load_start<=1;state<=HEADER;timer<=0;end
    HEADER:if(write_req)begin writer_start<=1;state<=ACK;end
    ACK:begin
     if(writer_busy)write_ack<=1;
     if(write_ack && !write_req)begin write_ack<=0;state<=STREAM;end
    end
    STREAM:if(source_done && writer_done)begin state<=DRAIN;settle<=0;end
    DRAIN:begin
     // Covers the final CDC synchronizers and the controller's write queue.
     // BUSY is checked after the complete burst, never as per-word ready.
     if(!idle_sync || busy_sync)settle<=0;
     else if(settle==1023)begin complete[load_index]<=1;state<=NEXT;end
     else settle<=settle+1'b1;
    end
    NEXT:begin
     if(load_index==3)begin state<=DONE;ready_latched<=1;end
     else begin load_index<=load_index+1'b1;settle<=0;state<=CLEAR;retried<=0;end
    end
    RECOVER:if(parser_ready && !busy_sync)begin
     // Full queued bursts finish before a partial failed burst is discarded.
     if(settle==1023)begin state<=CLEAR;settle<=0;timer<=0;end
     else settle<=settle+1'b1;
    end else settle<=0;
    default:;
   endcase
  end
 end
endmodule
