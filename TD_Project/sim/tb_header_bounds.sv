`timescale 1ns/1ps
// Drive real header bytes through both real sd_sector_adapter instances.
// Only the directory metadata is supplied as a fixture; no header field,
// predicate, state, or sector-completion signal is forced.
module tb_header_bounds #(parameter SCALE=1);
 reg clk=0,rst=1,start=0,ack=0,valid=0,ending=0;
 reg[7:0]byte_in=0,header[0:511];
 reg[31:0]test_size=78;
 wire ready0,ready1,wr0,wr1,err0,err1,read0,read1;
 wire[3:0]code0,code1;
 wire[31:0]addr0,addr1;
 reg compare_on=0;
 integer cases=0,accepted=0,rejected=0;
 always #5 clk=~clk;
 fat32_bmp_read #(.ENABLE_SCALE(SCALE)) dut(
  .clk(clk),.rst(rst),.load_start(start),.load_sector(32'd0),.scan_start(1'b0),
  .sd_init_done(1'b1),.bmp_width(16'd4),.bmp_height(16'd2),.write_req_ack(ack),
  .sd_sec_read_data(byte_in),.sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),
  .ready(ready0),.write_req(wr0),.load_error(err0),.error_code(code0),
  .sd_sec_read(read0),.sd_sec_read_addr(addr0),.load_done(),.sd_recover_reset(),
  .header_file_len(),.header_pixel_offset(),.timeout_trace(),.timeout_lba(),
  .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
  .state_code(),.bmp_data_wr_en(),.bmp_data(),.bmp_top_down());
 p21_parser_reference #(.ENABLE_SCALE(SCALE)) reference_dut(
  .clk(clk),.rst(rst),.load_start(start),.load_sector(32'd0),.scan_start(1'b0),
  .sd_init_done(1'b1),.bmp_width(16'd4),.bmp_height(16'd2),.write_req_ack(ack),
  .sd_sec_read_data(byte_in),.sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),
  .ready(ready1),.write_req(wr1),.load_error(err1),.error_code(code1),
  .sd_sec_read(read1),.sd_sec_read_addr(addr1),.load_done(),.sd_recover_reset(),
  .header_file_len(),.header_pixel_offset(),.timeout_trace(),.timeout_lba(),
  .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
  .state_code(),.bmp_data_wr_en(),.bmp_data(),.bmp_top_down());
 always @(negedge clk)if(compare_on && !rst)begin
  if({ready0,wr0,err0,read0,code0,addr0,dut.state} !==
     {ready1,wr1,err1,read1,code1,addr1,reference_dut.state})
   $fatal(1,"cycle mismatch case%0d state%0d/%0d code%h/%h",cases,dut.state,reference_dut.state,code0,code1);
  if(dut.state==5 && dut.bounds_ok!==reference_dut.bounds_ok)
   $fatal(1,"bounds verdict not settled at HCHECK");
  if(dut.state==5 && dut.format_ok!==
    (dut.magic0=="B" && dut.magic1=="M" && dut.dib>=40 && dut.planes==1 &&
     dut.dimensions_ok && dut.bpp==24 && dut.compression==0 && dut.expected_pixels!=0))
   $fatal(1,"cached format differs from original predicate at HCHECK");
 end
 task put32(input integer pos,input reg[31:0]value);
  for(integer j=0;j<4;j++)header[pos+j]=value>>(8*j);
 endtask
 function[31:0]get32(input integer pos);
  get32={header[pos+3],header[pos+2],header[pos+1],header[pos]};
 endfunction
 task default_header;
  for(integer j=0;j<512;j++)header[j]=0;
  header[0]="B";header[1]="M";put32(2,78);put32(10,54);put32(14,40);
  put32(18,4);put32(22,2);header[26]=1;header[28]=24;test_size=78;
 endtask
 function bit should_accept;
  longint unsigned w,h,off,len,size,bytes_needed;
  longint signed sh;
  bit dimensions;
  w=get32(18);sh=$signed(get32(22));h=sh<0 ? -sh : sh;
  off=get32(10);len=get32(2);size=test_size;
  dimensions=SCALE ? (w>=1 && w<=1920 && h>=1 && h<=1080) : (w==4 && sh==2);
  bytes_needed=SCALE ? ((w*3+3)/4)*4*h : 24;
  should_accept=header[0]=="B" && header[1]=="M" && get32(14)>=40 &&
    {header[27],header[26]}==1 && {header[29],header[28]}==24 && get32(30)==0 &&
    dimensions && off>=54 && off<len && len<=size && off+bytes_needed<=len;
 endfunction
 task reset_parser;
  @(negedge clk);rst=1;valid=0;ending=0;start=0;ack=0;
  repeat(4)@(negedge clk);rst=0;
  repeat(4)@(negedge clk);
 endtask
 task check_header(input integer bytes_sent,input bit last_end,input bit gaps);
  bit expected;
  integer cycles;
  expected=should_accept();
  wait(ready0 && ready1);@(negedge clk);start=1;
  @(negedge clk);start=0;
  wait(read0 && read1);
  for(integer j=0;j<bytes_sent;j++)begin
   @(negedge clk);byte_in=header[j];valid=1;ending=last_end && j==bytes_sent-1;
   if(gaps && j%7==0)begin @(negedge clk);valid=0;end
  end
  @(negedge clk);valid=0;
  if(!last_end)begin repeat(2)@(negedge clk);ending=1;@(negedge clk);end
  ending=0;cycles=0;
  while(!wr0 && !err0 && cycles<30)begin @(negedge clk);cycles++;end
  if(!wr0 && !err0)$fatal(1,"header result timeout");
  if(bytes_sent!=512)begin
   if(!err0 || code0!=2)$fatal(1,"short sector not rejected as transport error");
  end else if(expected)begin
   if(!wr0 || err0 || code0!=0)$fatal(1,"valid header rejected case%0d",cases);
   accepted++;
  end else begin
   if(!err0 || wr0 || code0!=1)$fatal(1,"invalid header accepted case%0d",cases);
   rejected++;
  end
  cases++;
  if(wr0)reset_parser(); // Full streaming/pixels covered by scale_preload.
  else repeat(5)@(negedge clk); // Invalid -> next load, without reset.
 endtask
 initial begin
  force dut.resources=4'hf;force reference_dut.resources=4'hf;
  force dut.c0=32'd10;force reference_dut.c0=32'd10;
  force dut.z0=test_size;force reference_dut.z0=test_size;
  force dut.max_cluster=32'd100000;force reference_dut.max_cluster=32'd100000;
  force dut.spc=8'd8;force reference_dut.spc=8'd8;
  force dut.data_lba=32'd20000;force reference_dut.data_lba=32'd20000;
  reset_parser();compare_on=1;
  default_header();check_header(512,1,0);
  default_header();check_header(512,0,1);
  for(integer fault=0;fault<22;fault++)begin
   default_header();
   case(fault)
    0:header[0]=0;1:header[1]=0;2:put32(14,39);3:header[26]=2;
    4:header[27]=1;5:header[28]=32;6:put32(30,1);7:put32(30,32'h80000000);
    8:put32(10,53);9:put32(10,78);10:put32(10,79);11:put32(2,79);
    12:put32(2,77);13:put32(18,0);14:put32(18,1921);15:put32(22,0);
    16:put32(22,1081);17:put32(22,32'h80000000);18:put32(22,32'h7fffffff);
    19:put32(18,32'hffffffff);20:put32(22,-2);21:put32(14,108);
   endcase
   check_header(512,fault%2,fault%3==0);
   default_header();check_header(512,1,0); // Invalid/valid alternation.
  end
  for(integer k=0;k<128;k++)begin
   default_header();
   case(k%4)
    0:begin // Exact/short bound near 32-bit overflow; wide addition required.
     put32(10,32'hfffffff0-k);put32(2,32'hffffffff);test_size=32'hffffffff;
    end
    1:begin // Variable offset with exact or one-byte-short pixel extent.
     put32(10,54+k*11);put32(2,78+k*11-(k%3==0));test_size=get32(2);
    end
    2:begin // Padded source rows and negative heights at scaling limits.
     put32(18,(k%2) ? 1920 : 641);put32(22,-1080);
     put32(2,54+((get32(18)*3+3)/4)*4*1080-(k%3==0));test_size=get32(2);
    end
    3:begin put32(10,$random);put32(2,$random);test_size=32'hffffffff;end
   endcase
   check_header(512,k%2,k%5==0);
  end
  default_header();check_header(34,1,0);
  default_header();check_header(511,0,0);
  // Abort mid-header: reset both parser and transport, then load a fresh file.
  default_header();wait(ready0 && ready1);@(negedge clk);start=1;
  @(negedge clk);start=0;wait(read0 && read1);
  for(integer j=0;j<26;j++)begin @(negedge clk);valid=1;byte_in=header[j];end
  reset_parser();
  if(wr0 || err0 || !ready0)$fatal(1,"reset retained a partial header result");
  default_header();check_header(512,1,0);
  $display("TB_PASS header bounds SCALE=%0d: %0d cases, accepted%0d rejected%0d; cycle-equivalent to P21",SCALE,cases,accepted,rejected);
  $finish;
 end
 initial begin #10000000;$fatal(1,"header test timeout");end
endmodule
