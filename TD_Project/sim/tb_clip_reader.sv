`timescale 1ns/1ps
module tb_clip_reader;
 reg mc=0,pc=0,rst=0,fs=0;always #5 mc=~mc;always #20 pc=~pc;
 reg[20:0]base=1228800;wire rd,valid,pvalid,busy,under;wire[20:0]addr;
 wire[23:0]rgb;wire[7:0]error;wire[31:0]data;
 reg consume_enable=0;
 media_frame_reader #(.ENABLE_CLIP(1),.MAX_INFLIGHT_BURSTS(1)) dut(
  .mem_clk(mc),.mem_rst_n(rst),.controller_init_done(rst),.controller_busy(1'b0),.refresh_active(1'b0),
  .app_rd_en(rd),.app_rd_addr(addr),.sdram_rd_valid(valid),.sdram_rd_data(data),
  .pix_clk(pc),.pix_rst_n(rst),.frame_start(fs),.active_index(2'd0),.thumbnail_mode(1'b0),
  .clip_mode(1'b1),.clip_base(base),.pixel_consume(consume_enable && pvalid),
  .pixel_rgb(rgb),.pixel_valid(pvalid),.underflow(under),.reader_busy(busy),.frame_read_done(),.reader_index(),.reader_error(error));
 reg[31:0]words[0:383999];reg[20:0]q[0:1023];
 integer wp=0,rp=0,cycles=0,burst=0,reads=0,consumed=0,current_frame=0,frame_reads=0;
 integer previous_address=0;reg previous_rd=0;reg rv=0;reg[31:0]rddata=0;
 assign valid=rv;assign data=rddata;
 always @(posedge mc)begin
  cycles++;rv<=0;
  if(rst && rd)begin
   if(addr!=base+frame_reads || addr>=1612800)$fatal(1,"reader address f%0d req%0d addr%h",current_frame,frame_reads,addr);
   if(burst!=0 && addr!=previous_address+1)$fatal(1,"non-contiguous clip request");
   q[wp%1024]=addr;wp++;reads++;frame_reads++;burst++;previous_address=addr;
  end
  if(previous_rd && !rd)begin if(burst!=128)$fatal(1,"burst size %0d",burst);burst=0;end
  previous_rd=rd;
  if(rst && rp<wp && cycles%2==0 && cycles%700>=35)begin
   rddata<=words[q[rp%1024]-1228800];rp++;rv<=1;
  end
 end
 always @(posedge pc)if(rst && consume_enable && pvalid)begin
  if(rgb!==words[current_frame*19200+consumed][23:0])$fatal(1,"clip FIFO pixel f%0d n%0d",current_frame,consumed);
  consumed++;
 end
 initial begin
  $readmemh("clip_words.hex",words);repeat(5)@(negedge pc);rst=1;
  for(integer f=0;f<20;f++)begin
   @(negedge pc);current_frame=f;base=1228800+f*19200;consumed=0;frame_reads=0;fs=1;
   @(negedge pc);fs=0;repeat(50)@(negedge pc);consume_enable=1;
   wait(consumed==19200);@(negedge pc);consume_enable=0;
   wait(!busy);repeat(20)@(negedge pc);
   if(error || under || frame_reads!=19200 || wp!=rp)$fatal(1,"reader completion error%h under%b reads%0d",error,under,frame_reads);
  end
  if(reads!=384000)$fatal(1,"total reads");
  $display("TB_PASS all 20 actual clip frames: 384000 source words, base/length changes, exact FIFO pixel order, refresh pauses and 128-word read bursts");$finish;
 end
 initial begin #40000000;$fatal(1,"timeout frame%0d consumed%0d",current_frame,consumed);end
endmodule
