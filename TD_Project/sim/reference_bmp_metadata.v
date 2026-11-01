`timescale 1ns/1ps
// Lecture 7 minimal integration: scanner + file streamer + sector adapter.
// scan_found_sector/load_sector are now opaque file IDs 0..3, NOT raw LBAs.
// Cluster/size tables remain owned by the MiCu volume scanner.
module reference_bmp_metadata #(
 parameter integer CLK_FREQ_HZ=100000000,ENABLE_SCALE=0,
 parameter integer SD_READ_TIMEOUT_MS=500,SD_REINIT_TIMEOUT_MS=2000
)(
 input wire clk,rst, output wire ready,
 output reg load_done,load_error,output reg[3:0]error_code,
 output wire sd_recover_reset,
 output wire[31:0]header_file_len,header_pixel_offset,
 output reg[31:0]timeout_trace,timeout_lba,
 input wire scan_start,
 output reg scan_done,scan_found_valid,output reg[31:0]scan_found_sector,
 output reg[2:0]scan_found_total,
 input wire load_start,input wire[31:0]load_sector,
 input wire sd_init_done,output wire[3:0]state_code,
 input wire[15:0]bmp_width,bmp_height,
 output reg write_req,input wire write_req_ack,
 output wire sd_sec_read,output wire[31:0]sd_sec_read_addr,
 input wire[7:0]sd_sec_read_data,input wire sd_sec_read_data_valid,sd_sec_read_end,
 output reg bmp_data_wr_en,output reg[23:0]bmp_data,
 output wire bmp_top_down
);
 localparam IDLE=0,SCAN=1,EMIT=2,HREQ=3,HWAIT=4,HCHECK=5,
            ACK_HIGH=6,ACK_LOW=7,STREAM=8,FAIL=9,RESET_SD=10,REINIT=11,HALT=12,FINISH_CHECK=13;
 localparam integer TIMEOUT=(CLK_FREQ_HZ/1000)*SD_READ_TIMEOUT_MS;
 localparam integer REINIT_WAIT=(CLK_FREQ_HZ/1000)*SD_REINIT_TIMEOUT_MS;
 localparam integer TIMER_LIMIT=TIMEOUT>REINIT_WAIT ? TIMEOUT : REINIT_WAIT;
 localparam integer TIMER_WIDTH=TIMER_LIMIT>16 ? $clog2(TIMER_LIMIT+1) : 5;
 reg[3:0]state;
 // All incrementing states stop/reset at TIMEOUT-1, REINIT_WAIT-1 or 15.
 // Keep every reachable count; remove only unreachable high counter bits.
 reg[TIMER_WIDTH-1:0]timer;
 reg scan_retry,recover_scan;
 reg[2:0]emit_index;
 reg scanner_start,stream_start,header_req;
 wire scanner_busy,scanner_done,stream_busy,stream_done;
 wire[7:0]scan_error,stream_error,spc;
 wire[31:0]partition,fat_lba,data_lba,max_cluster;
 wire[3:0]resources;
 wire[31:0]c0,c1,c2,c3,z0,z1,z2,z3;
 reg[31:0]selected_cluster,selected_size,header_lba;
 reg[31:0]header_bias,header_sectors;
 reg[2:0]cluster_shift;
 function[2:0]spc_shift;
  input[7:0]value;
  begin case(value)
   2:spc_shift=1;4:spc_shift=2;8:spc_shift=3;16:spc_shift=4;
   32:spc_shift=5;64:spc_shift=6;128:spc_shift=7;default:spc_shift=0;
  endcase end
 endfunction
 wire scan_req,stream_req;
 wire[31:0]scan_lba,stream_lba;
 wire sector_busy,sector_valid,sector_done;
 wire[7:0]sector_byte,sector_error;
 wire[8:0]sector_index;
 wire stream_valid;
 wire[7:0]stream_byte;
 wire[31:0]stream_offset;
 reg[7:0]last_fs_error;
 reg[7:0]magic0,magic1;
 reg[31:0]file_len,offset,dib,width,height,compression;
 reg[15:0]planes,bpp;
 reg[31:0]pixels;
 reg[1:0]rgb_index;
 reg[7:0]blue,green;
 reg[2:0]ack_sync;
 wire[31:0]expected_pixels=bmp_width*bmp_height;
 // Snapshot the original pre-edge count verdict independently of the state
 // mux. FINISH_CHECK consumes the verdict captured on the completion edge.
 // Pixel emission is unchanged; completion/count-error notification is +1 clk.
 reg finish_bad_count;
 always @(posedge clk or posedge rst)begin
  if(rst)finish_bad_count<=0;
  else finish_bad_count<=pixels!=expected_pixels || rgb_index!=0;
 end
 wire[31:0]absolute_height=height[31] ? (~height+1'b1) : height;
 reg[12:0]source_stride;
 reg[10:0]source_height_q;
 reg[23:0]source_bytes;
 reg[34:0]source_end;
 // Header dimensions end at byte 25; validation follows the complete
 // 512-byte header sector. Thus these three arithmetic stages have settled
 // long before HCHECK, without weakening the real 100 MHz timing constraint.
 always @(posedge clk)begin
  source_stride<=({1'b0,width[10:0],1'b0}+{2'd0,width[10:0]}+13'd3)&13'h1ffc;
  source_height_q<=absolute_height[10:0];
  source_bytes<=source_stride*source_height_q;
  source_end<={3'd0,offset}+{11'd0,source_bytes};
 end
 wire[34:0]pixel_end=ENABLE_SCALE ? source_end :
                                  {3'd0,offset}+{3'd0,expected_pixels}*35'd3;
 // Header dimensions finish at byte 25, hundreds of clocks before HCHECK.
 // Cache their verdict to break negate/compare -> parser state timing, just
 // as source_end above is staged. No pixel or sector sequencing is changed.
 reg scale_dimensions_ok;
 always @(posedge clk)begin
  scale_dimensions_ok<=width>=1 && width<=1920 && absolute_height>=1 && absolute_height<=1080;
 end
 wire dimensions_ok=ENABLE_SCALE ? scale_dimensions_ok :
    (width=={16'd0,bmp_width} && height=={16'd0,bmp_height} && bmp_width[1:0]==0);
 reg[3:0]header_format;
 wire format_ok=(&header_format) && dimensions_ok;
 // These fields finish by byte 25; the adapter accepts only a complete
 // 512-byte sector before HCHECK. Register each unchanged bounds predicate
 // separately to remove the 32/35-bit comparisons from the state/error mux.
 reg[3:0]header_bounds;
 always @(posedge clk or posedge rst)begin
  if(rst)begin header_bounds<=0;header_format<=0;end
  else if(state==IDLE && load_start)begin header_bounds<=0;header_format<=0;end
  else begin
   // Format bytes finish by byte 33, well before the complete sector check.
   // Keep the original predicates, but isolate them from timer/state enables.
   header_format[0]<=magic0=="B" && magic1=="M";
   header_format[1]<=dib>=40 && planes==1;
   header_format[2]<=bpp==24 && compression==0;
   header_format[3]<=expected_pixels!=0;
   header_bounds[0]<=offset>=54;
   header_bounds[1]<=offset<file_len;
   header_bounds[2]<=file_len<=selected_size;
   header_bounds[3]<=pixel_end<={3'd0,file_len};
  end
 end
 wire bounds_ok=&header_bounds;
 assign bmp_top_down=ENABLE_SCALE && height[31];
 wire scale_pause,scale_done,scale_error,scale_valid;
 wire[23:0]scale_rgb;
 generate if(ENABLE_SCALE)begin:g_scale
  bmp_nn_resampler u_scale(.clk(clk),.rst(rst || state==RESET_SD),.start(stream_start),
   .source_width(width[10:0]),.source_height(absolute_height[10:0]),
   .dest_width(bmp_width[10:0]),.dest_height(bmp_height[10:0]),
   .top_down(height[31]),.pixel_offset(offset),
   .file_valid(stream_valid && state==STREAM),.file_byte(stream_byte),.file_done(stream_done),
   .sector_pause(scale_pause),.done(scale_done),.error(scale_error),
   .pixel_valid(scale_valid),.pixel_rgb(scale_rgb));
 end else begin:g_no_scale
  assign scale_pause=0;assign scale_done=0;assign scale_error=0;
  assign scale_valid=0;assign scale_rgb=0;
 end endgenerate
 assign ready=(state==IDLE) && sd_init_done;
 assign sd_recover_reset=(state==RESET_SD);
 assign state_code=state==IDLE ? 4'd1 : state==SCAN || state==EMIT ? 4'd0 :
                   state==HALT ? 4'he : 4'd2;
 assign header_file_len=error_code==9 ? {24'd0,last_fs_error} : file_len;
 assign header_pixel_offset=error_code==9 ? sd_sec_read_addr : offset;
 wire adapter_req=state==SCAN ? scan_req : state==STREAM ? stream_req : header_req;
 wire[31:0]adapter_lba=state==SCAN ? scan_lba : state==STREAM ? stream_lba : header_lba;
 sd_sector_adapter #(.TIMEOUT_CYCLES(TIMEOUT)) u_sector(
  .clk(clk),.rst(rst || sd_recover_reset),.enable(sd_init_done),
  .sector_req(adapter_req),.sector_lba(adapter_lba),.sector_busy(sector_busy),
  .sector_valid(sector_valid),.sector_byte(sector_byte),.sector_byte_index(sector_index),
  .sector_done(sector_done),.sector_error(sector_error),
  .sd_sec_read(sd_sec_read),.sd_sec_read_addr(sd_sec_read_addr),
  .sd_sec_read_data_valid(sd_sec_read_data_valid),.sd_sec_read_data(sd_sec_read_data),
  .sd_sec_read_end(sd_sec_read_end));
 fat32_volume_scanner u_volume(
  .clk(clk),.rst_n(!rst),.scan_start(scanner_start),.scan_busy(scanner_busy),
  .scan_done(scanner_done),.fs_error(scan_error),.partition_lba(partition),
  .sectors_per_cluster(spc),.fat_start_lba(fat_lba),.data_start_lba(data_lba),
  .max_cluster(max_cluster),.resource_valid(resources),
  .resource0_cluster(c0),.resource1_cluster(c1),.resource2_cluster(c2),.resource3_cluster(c3),
  .resource0_size(z0),.resource1_size(z1),.resource2_size(z2),.resource3_size(z3),
  .sector_req(scan_req),.sector_lba(scan_lba),.sector_busy(sector_busy),
  .sector_valid(sector_valid && state==SCAN),.sector_byte(sector_byte),
  .sector_byte_index(sector_index),.sector_done(sector_done && state==SCAN),
  .sector_error(sector_error));
 fat32_file_streamer u_stream(
  .clk(clk),.rst_n(!rst && state!=RESET_SD),.file_start(stream_start),
  .first_cluster(selected_cluster),.file_size(selected_size),
  .sectors_per_cluster(spc),.fat_start_lba(fat_lba),.data_start_lba(data_lba),
  .max_cluster(max_cluster),.file_busy(stream_busy),.file_done(stream_done),
  .file_valid(stream_valid),.file_byte(stream_byte),.file_byte_offset(stream_offset),
  .fs_error(stream_error),.sector_req(stream_req),.sector_lba(stream_lba),
  .sector_busy(sector_busy || scale_pause),.sector_valid(sector_valid && state==STREAM),
  .sector_byte(sector_byte),.sector_byte_index(sector_index),
  .sector_done(sector_done && state==STREAM),.sector_error(sector_error));
 function[31:0]cluster_at;
  input[1:0]id;
  begin case(id)0:cluster_at=c0;1:cluster_at=c1;2:cluster_at=c2;3:cluster_at=c3;endcase end
 endfunction
 // Passive first-timeout record survives SD recovery and file retries.
 // D6 / parser state / reason (1=sector,2=ACK high,3=ACK low) / byte index mod 512.
 always @(posedge clk or posedge rst)begin
  if(rst)begin timeout_trace<=0;timeout_lba<=0;end
  else if(timeout_trace==0)begin
   if(sector_done && sector_error==1 && (state==SCAN || state==HWAIT || state==STREAM))begin
    timeout_trace<={8'hd6,state,4'd1,7'd0,sector_index};timeout_lba<=sd_sec_read_addr;
   end else if(state==ACK_HIGH && !ack_sync[2] && timer>=TIMEOUT-1)begin
    timeout_trace<={8'hd6,state,4'd2,16'd0};timeout_lba<=sd_sec_read_addr;
   end else if(state==ACK_LOW && ack_sync[2] && timer>=TIMEOUT-1)begin
    timeout_trace<={8'hd6,state,4'd3,16'd0};timeout_lba<=sd_sec_read_addr;
   end
  end
 end
 function[31:0]size_at;
  input[1:0]id;
  begin case(id)0:size_at=z0;1:size_at=z1;2:size_at=z2;3:size_at=z3;endcase end
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)ack_sync<=0;else ack_sync<={ack_sync[1:0],write_req_ack};
 end
 // Same strict BMP header contract as the preceding successful parser.
 always @(posedge clk or posedge rst)begin
  if(rst)begin magic0<=0;magic1<=0;file_len<=0;offset<=0;dib<=0;
    width<=0;height<=0;compression<=0;planes<=0;bpp<=0;end
  else if(state==IDLE && load_start)begin
    magic0<=0;magic1<=0;file_len<=0;offset<=0;dib<=0;
    width<=0;height<=0;compression<=0;planes<=0;bpp<=0;
  end else if(state==HWAIT && sector_valid)begin
   case(sector_index)
    0:magic0<=sector_byte;1:magic1<=sector_byte;
    2:file_len[7:0]<=sector_byte;3:file_len[15:8]<=sector_byte;
    4:file_len[23:16]<=sector_byte;5:file_len[31:24]<=sector_byte;
    10:offset[7:0]<=sector_byte;11:offset[15:8]<=sector_byte;
    12:offset[23:16]<=sector_byte;13:offset[31:24]<=sector_byte;
    14:dib[7:0]<=sector_byte;15:dib[15:8]<=sector_byte;
    16:dib[23:16]<=sector_byte;17:dib[31:24]<=sector_byte;
    18:width[7:0]<=sector_byte;19:width[15:8]<=sector_byte;
    20:width[23:16]<=sector_byte;21:width[31:24]<=sector_byte;
    22:height[7:0]<=sector_byte;23:height[15:8]<=sector_byte;
    24:height[23:16]<=sector_byte;25:height[31:24]<=sector_byte;
    26:planes[7:0]<=sector_byte;27:planes[15:8]<=sector_byte;
    28:bpp[7:0]<=sector_byte;29:bpp[15:8]<=sector_byte;
    30:compression[7:0]<=sector_byte;31:compression[15:8]<=sector_byte;
    32:compression[23:16]<=sector_byte;33:compression[31:24]<=sector_byte;
   endcase
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;timer<=0;scan_retry<=0;recover_scan<=0;emit_index<=0;
   scanner_start<=0;stream_start<=0;header_req<=0;
   load_done<=0;load_error<=0;error_code<=0;last_fs_error<=0;
   scan_done<=0;scan_found_valid<=0;scan_found_sector<=0;scan_found_total<=0;
   selected_cluster<=0;selected_size<=0;header_lba<=0;
   header_bias<=0;header_sectors<=0;cluster_shift<=0;
   write_req<=0;bmp_data_wr_en<=0;bmp_data<=0;pixels<=0;rgb_index<=0;blue<=0;green<=0;
  end else begin
   scanner_start<=0;stream_start<=0;header_req<=0;scan_found_valid<=0;
   load_done<=0;load_error<=0;bmp_data_wr_en<=0;
   // Three registered stages; HREQ waits until all address stages are valid.
   cluster_shift<=spc_shift(spc);
   header_bias<=selected_cluster-2;
   header_sectors<=header_bias << cluster_shift;
   header_lba<=data_lba+header_sectors;
   if(ENABLE_SCALE && state==STREAM && scale_valid)begin
    bmp_data<=scale_rgb;bmp_data_wr_en<=1;pixels<=pixels+1'b1;
   end
   if(!ENABLE_SCALE && state==STREAM && stream_valid && stream_offset>=offset &&
      {3'd0,stream_offset}<pixel_end)begin
    case(rgb_index)
     0:begin blue<=stream_byte;rgb_index<=1;end
     1:begin green<=stream_byte;rgb_index<=2;end
     2:begin bmp_data<={stream_byte,green,blue};bmp_data_wr_en<=1;
        pixels<=pixels+1'b1;rgb_index<=0;end
    endcase
   end
   // Timeout means the physical transaction may still be active: reset only SD.
   if(sector_done && sector_error==1 && (state==SCAN || state==HWAIT || state==STREAM))begin
    recover_scan<=state==SCAN;write_req<=0;error_code<=6;timer<=0;state<=RESET_SD;
   end else case(state)
    IDLE:begin
     timer<=0;
     if(scan_start && sd_init_done)begin
      scan_done<=0;scan_found_total<=0;scan_retry<=0;error_code<=0;
      scanner_start<=1;state<=SCAN;
     end else if(load_start && sd_init_done)begin
      error_code<=0;last_fs_error<=0;pixels<=0;rgb_index<=0;
      selected_cluster<=cluster_at(load_sector[1:0]);selected_size<=size_at(load_sector[1:0]);
      if(load_sector>3 || resources!=15)begin error_code<=9;last_fs_error<=8'h22;state<=FAIL;end
      else if(cluster_at(load_sector[1:0])<2 || cluster_at(load_sector[1:0])>max_cluster ||
              size_at(load_sector[1:0])<54)begin error_code<=9;last_fs_error<=8'h24;state<=FAIL;end
      else begin timer<=0;state<=HREQ;end
     end
    end
    SCAN:if(scanner_done)begin
     if(scan_error!=0 || resources!=15)begin
      error_code<=9;last_fs_error<=scan_error;scan_done<=1;state<=FAIL;
     end else begin emit_index<=0;state<=EMIT;end
    end
    EMIT:begin
     if(emit_index<4)begin
      scan_found_valid<=1;scan_found_sector<={30'd0,emit_index[1:0]};
      scan_found_total<=emit_index+1'b1;emit_index<=emit_index+1'b1;
     end else begin scan_done<=1;state<=IDLE;end
    end
    HREQ:begin
     if(timer<3)timer<=timer+1'b1;
     else if(!sector_busy)begin header_req<=1;state<=HWAIT;timer<=0;end
    end
    HWAIT:if(sector_done)begin
     if(sector_error!=0)begin error_code<=2;state<=FAIL;end
     else state<=HCHECK;
    end
    HCHECK:begin
     if(!format_ok || !bounds_ok)begin error_code<=1;state<=FAIL;end
     else begin write_req<=1;timer<=0;state<=ACK_HIGH;end
    end
    ACK_HIGH:begin
     if(ack_sync[2])begin write_req<=0;timer<=0;state<=ACK_LOW;end
     else if(timer>=TIMEOUT-1)begin write_req<=0;error_code<=6;state<=FAIL;end
     else timer<=timer+1'b1;
    end
    ACK_LOW:begin
     if(!ack_sync[2])begin stream_start<=1;state<=STREAM;end
     else if(timer>=TIMEOUT-1)begin error_code<=6;state<=FAIL;end
     else timer<=timer+1'b1;
    end
    STREAM:if(stream_done && stream_error!=0)begin
     error_code<=9;last_fs_error<=stream_error;state<=FAIL;
    // start clears the scaler's sticky completion/error on this same edge;
    // do not consume the previous file's flags before that edge completes.
    end else if(ENABLE_SCALE && scale_error && !stream_start)begin error_code<=3;state<=FAIL;
    end else if(ENABLE_SCALE ? (scale_done && !stream_start) : stream_done)begin
     if(stream_error!=0)begin error_code<=9;last_fs_error<=stream_error;state<=FAIL;end
     else state<=FINISH_CHECK;
    end
    FINISH_CHECK:begin
     if(finish_bad_count)begin error_code<=3;state<=FAIL;end
     else begin load_done<=1;state<=IDLE;end
    end
    FAIL:begin load_error<=1;write_req<=0;state<=IDLE;end
    RESET_SD:begin
     if(timer==15)begin timer<=0;state<=REINIT;end else timer<=timer+1'b1;
    end
    REINIT:begin
     if(sd_init_done)begin
      timer<=0;
      if(recover_scan && !scan_retry)begin scan_retry<=1;scanner_start<=1;state<=SCAN;end
      else begin if(recover_scan)scan_done<=1;state<=FAIL;end
     end else if(timer>=REINIT_WAIT-1)begin
      error_code<=7;load_error<=1;scan_done<=1;state<=HALT;
     end else timer<=timer+1'b1;
    end
    HALT:write_req<=0;
    default:begin error_code<=5;state<=FAIL;end
   endcase
  end
 end
endmodule
