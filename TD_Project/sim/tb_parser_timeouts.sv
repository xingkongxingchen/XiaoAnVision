`timescale 1ns/1ps
module tb_parser_timeouts #(parameter LIMIT=700,REINIT=1400);
 reg clk=0,rst=1,start=0,ack=0,init=1,valid=0,ending=0,compare_on=0;
 reg[7:0]byte_in=0,header[0:511];
 always #5 clk=~clk;
 wire[1:0]ready,wr,err,read_req,recover;
 wire[3:0]code[0:1];wire[31:0]addr[0:1];
 fat32_bmp_read #(.CLK_FREQ_HZ(1000),.SD_READ_TIMEOUT_MS(LIMIT),.SD_REINIT_TIMEOUT_MS(REINIT)) dut(
  .clk(clk),.rst(rst),.load_start(start),.load_sector(32'd0),.scan_start(1'b0),.sd_init_done(init),
  .bmp_width(16'd4),.bmp_height(16'd2),.write_req_ack(ack),.sd_sec_read_data(byte_in),
  .sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),.ready(ready[0]),.write_req(wr[0]),
  .load_error(err[0]),.error_code(code[0]),.sd_sec_read(read_req[0]),.sd_sec_read_addr(addr[0]),.sd_recover_reset(recover[0]),
  .load_done(),.header_file_len(),.header_pixel_offset(),.timeout_trace(),.timeout_lba(),
  .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),.state_code(),.bmp_data_wr_en(),.bmp_data(),.bmp_top_down());
 reference_fat32_bmp_read #(.CLK_FREQ_HZ(1000),.SD_READ_TIMEOUT_MS(LIMIT),.SD_REINIT_TIMEOUT_MS(REINIT)) reference_dut(
  .clk(clk),.rst(rst),.load_start(start),.load_sector(32'd0),.scan_start(1'b0),.sd_init_done(init),
  .bmp_width(16'd4),.bmp_height(16'd2),.write_req_ack(ack),.sd_sec_read_data(byte_in),
  .sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),.ready(ready[1]),.write_req(wr[1]),
  .load_error(err[1]),.error_code(code[1]),.sd_sec_read(read_req[1]),.sd_sec_read_addr(addr[1]),.sd_recover_reset(recover[1]),
  .load_done(),.header_file_len(),.header_pixel_offset(),.timeout_trace(),.timeout_lba(),
  .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),.state_code(),.bmp_data_wr_en(),.bmp_data(),.bmp_top_down());
 always @(negedge clk)if(compare_on && !rst)begin
  if({ready[0],wr[0],err[0],read_req[0],recover[0],code[0],addr[0],dut.state} !==
     {ready[1],wr[1],err[1],read_req[1],recover[1],code[1],addr[1],reference_dut.state} || dut.timer!==reference_dut.timer)
   $fatal(1,"timeout cycle/value mismatch state%d/%d timer%d/%d",dut.state,reference_dut.state,dut.timer,reference_dut.timer);
 end
 task reset_parser;
  @(negedge clk);rst=1;start=0;ack=0;init=1;valid=0;ending=0;
  repeat(5)@(negedge clk);rst=0;compare_on=1;
  repeat(4)@(negedge clk);
 endtask
 task begin_load;
  wait(&ready);@(negedge clk);start=1;@(negedge clk);start=0;wait(&read_req);
 endtask
 task send_header(input integer length);
  for(integer k=0;k<length;k++)begin @(negedge clk);byte_in=header[k];valid=1;end
  @(negedge clk);valid=0;ending=1;@(negedge clk);ending=0;
 endtask
 task expect_error(input[3:0]expected);
  integer cycles;
  cycles=0;
  while(err!=3 && cycles<4*(LIMIT+REINIT))begin @(negedge clk);cycles++;end
  if(err!=3 || code[0]!==expected || code[1]!==expected)$fatal(1,"expected timeout error %h got%h/%h",expected,code[0],code[1]);
 endtask
 initial begin
  for(integer i=0;i<512;i++)header[i]=0;
  header[0]="B";header[1]="M";header[2]=78;header[10]=54;header[14]=40;
  header[18]=4;header[22]=2;header[26]=1;header[28]=24;
  force dut.resources=15;force reference_dut.resources=15;
  force dut.c0=10;force reference_dut.c0=10;force dut.z0=78;force reference_dut.z0=78;
  force dut.max_cluster=100000;force reference_dut.max_cluster=100000;
  force dut.spc=8;force reference_dut.spc=8;force dut.data_lba=20000;force reference_dut.data_lba=20000;
  reset_parser();begin_load();send_header(512);expect_error(6); // ACK high never arrives.
  reset_parser();begin_load();send_header(512);wait(&wr);@(negedge clk);ack=1;
  wait(dut.state==7);expect_error(6); // ACK low never arrives.
  reset_parser();begin_load();@(negedge clk);init=0;
  expect_error(7);if(dut.state!=12 || dut.timer!=REINIT-1)$fatal(1,"reinit deadline/HALT changed");
  reset_parser();begin_load();@(negedge clk);init=0;
  wait(&recover);wait(dut.state==11);repeat(20)@(negedge clk);init=1;expect_error(6);
  reset_parser();begin_load();send_header(511);expect_error(2);
  $display("TB_PASS reduced timer cycle-equivalent to 32-bit reference: ACK high/low, sector stall, 16-cycle SD reset, reinit success/deadline, short sector LIMIT=%0d REINIT=%0d",LIMIT,REINIT);
  $finish;
 end
 initial begin #10000000;$fatal(1,"parser timeout test timeout");end
endmodule
