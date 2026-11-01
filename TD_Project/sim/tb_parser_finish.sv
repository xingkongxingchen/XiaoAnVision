`timescale 1ns/1ps
// Isolate the parser's child-stream boundary; real header-sector adapter and
// ACK entry are exercised. Child outputs are stimuli, not a TF-card model.
module tb_parser_finish #(parameter SCALE=1);
 reg clk=0,rst=1,start=0,ack=0,valid=0,ending=0;
 reg[7:0]byte_in=0,header[0:511];
 always #5 clk=~clk;
 wire rd0,rd1,ready0,ready1,wr0,wr1,done0,done1,err0,err1,pv0,pv1;
 wire[3:0]code0,code1;wire[23:0]pixel0,pixel1;
 fat32_bmp_read #(.ENABLE_SCALE(SCALE)) dut(
  .clk(clk),.rst(rst),.load_start(start),.load_sector(32'd0),.scan_start(1'b0),
  .sd_init_done(1'b1),.bmp_width(16'd4),.bmp_height(16'd2),.write_req_ack(ack),
  .sd_sec_read_data(byte_in),.sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),
  .sd_sec_read(rd0),.ready(ready0),.write_req(wr0),.load_done(done0),.load_error(err0),.error_code(code0),
  .bmp_data_wr_en(pv0),.bmp_data(pixel0),.sd_recover_reset(),.header_file_len(),.header_pixel_offset(),
  .timeout_trace(),.timeout_lba(),.scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
  .state_code(),.sd_sec_read_addr(),.bmp_top_down());
 p36_parser_reference #(.ENABLE_SCALE(SCALE)) ref_dut(
  .clk(clk),.rst(rst),.load_start(start),.load_sector(32'd0),.scan_start(1'b0),
  .sd_init_done(1'b1),.bmp_width(16'd4),.bmp_height(16'd2),.write_req_ack(ack),
  .sd_sec_read_data(byte_in),.sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),
  .sd_sec_read(rd1),.ready(ready1),.write_req(wr1),.load_done(done1),.load_error(err1),.error_code(code1),
  .bmp_data_wr_en(pv1),.bmp_data(pixel1),.sd_recover_reset(),.header_file_len(),.header_pixel_offset(),
  .timeout_trace(),.timeout_lba(),.scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total(),
  .state_code(),.sd_sec_read_addr(),.bmp_top_down());
 reg mock_valid=0,mock_done=0;reg[7:0]mock_error=0,mock_byte=0;
 reg[23:0]mock_rgb=0;reg[31:0]mock_offset=54;
 integer cycles=0,dut_at=-1,ref_at=-1,cases=0,pixel_checks=0;
 reg compare_pixels=0;
 always @(posedge clk)begin
  cycles=cycles+1;#1;
  if(!rst)begin
   if(done0||err0)dut_at=cycles;
   if(done1||err1)ref_at=cycles;
   if(compare_pixels)begin
    if(pv0!==pv1 || (pv0 && pixel0!==pixel1))$fatal(1,"Pixel sequence changed case=%0d",cases);
    if(pv0)pixel_checks=pixel_checks+1;
   end
  end
 end
 task reset_and_enter;
  @(negedge clk);rst=1;start=0;ack=0;valid=0;ending=0;mock_valid=0;mock_done=0;mock_error=0;compare_pixels=0;
  repeat(5)@(negedge clk);rst=0;repeat(5)@(negedge clk);
  dut_at=-1;ref_at=-1;
  wait(ready0&&ready1);start=1;@(negedge clk);start=0;wait(rd0&&rd1);
  for(integer b=0;b<512;b=b+1)begin @(negedge clk);valid=1;byte_in=header[b];end
  @(negedge clk);valid=0;ending=1;@(negedge clk);ending=0;
  wait(wr0&&wr1);@(negedge clk);ack=1;wait(dut.state==7&&ref_dut.state==7);
  @(negedge clk);ack=0;wait(dut.state==8&&ref_dut.state==8);
  repeat(3)@(negedge clk);compare_pixels=1;
 endtask
 task run_case(input integer number,input integer count,input bit simultaneous,input bit transport_error,input bit partial);
  integer timeout,expected_code,expected_delay;
  reset_and_enter();
  for(integer p=0;p<count;p=p+1)begin
   if(SCALE)begin
    mock_rgb=24'h123400+p;mock_valid=1;mock_done=simultaneous&&p==count-1;
    @(negedge clk);mock_valid=0;
   end else for(integer c=0;c<3;c=c+1)begin
    mock_offset=54+p*3+c;mock_byte=p*3+c;mock_valid=1;
    mock_done=simultaneous&&p==count-1&&c==2;
    @(negedge clk);mock_valid=0;
   end
   if(!mock_done && !(number==7 && p==count-1))repeat(2)@(negedge clk);
  end
  if(partial)begin mock_offset=75;mock_byte=8'hff;mock_valid=1;@(negedge clk);mock_valid=0;end
  if(!simultaneous)begin
   if(number!=7)repeat(2)@(negedge clk);
   mock_done=1;mock_error=transport_error?8'h25:0;
   @(negedge clk);
  end
  mock_done=0;mock_valid=0;timeout=0;
  while((dut_at<0||ref_at<0)&&timeout<20)begin @(negedge clk);timeout=timeout+1;end
  if(timeout==20)$fatal(1,"Completion missing case=%0d",number);
  // Non-scaled parser intentionally ignores bytes beyond pixel_end. Scaling
  // supplies decoded pixels directly, so an extra scale_valid is over-count.
  expected_code=transport_error?9:(((SCALE?count:(count>8?8:count))!=8||simultaneous||partial)?3:0);
  expected_delay=transport_error?0:1;
  if(code0!==expected_code || code1!==expected_code || dut_at!=ref_at+expected_delay)
    $fatal(1,"End contract case=%0d SCALE=%0d code=%h/%h ticks=%0d/%0d expected_delay=%0d",number,SCALE,code0,code1,dut_at,ref_at,expected_delay);
  cases=cases+1;
 endtask
 initial begin
  force dut.resources=15;force ref_dut.resources=15;
  force dut.c0=10;force ref_dut.c0=10;force dut.z0=512;force ref_dut.z0=512;
  force dut.max_cluster=100000;force ref_dut.max_cluster=100000;
  force dut.spc=8;force ref_dut.spc=8;force dut.data_lba=20000;force ref_dut.data_lba=20000;
  force dut.stream_valid=mock_valid;force ref_dut.stream_valid=mock_valid;
  force dut.stream_byte=mock_byte;force ref_dut.stream_byte=mock_byte;
  force dut.stream_offset=mock_offset;force ref_dut.stream_offset=mock_offset;
  force dut.stream_done=mock_done;force ref_dut.stream_done=mock_done;
  force dut.stream_error=mock_error;force ref_dut.stream_error=mock_error;
  force dut.scale_valid=mock_valid;force ref_dut.scale_valid=mock_valid;
  force dut.scale_rgb=mock_rgb;force ref_dut.scale_rgb=mock_rgb;
  force dut.scale_done=mock_done;force ref_dut.scale_done=mock_done;
  force dut.scale_error=0;force ref_dut.scale_error=0;
  for(integer b=0;b<512;b=b+1)header[b]=0;
  header[0]="B";header[1]="M";header[2]=78;header[10]=54;header[14]=40;
  header[18]=4;header[22]=2;header[26]=1;header[28]=24;
  run_case(0,8,0,0,0);run_case(1,7,0,0,0);run_case(2,9,0,0,0);
  run_case(3,8,1,0,0);run_case(4,8,0,1,0);run_case(5,0,0,0,0);
  run_case(7,8,0,0,0); // done directly follows the last accepted pixel
  if(!SCALE)run_case(6,8,0,0,1);
  reset_and_enter();mock_done=1;@(negedge clk);mock_done=0;
  if(dut.state!=13)$fatal(1,"Expected staged completion before reset");
  rst=1;#1;if(done0||err0||code0!=0)$fatal(1,"Reset leaked pending completion");
  repeat(3)@(negedge clk);rst=0;repeat(4)@(negedge clk);
  if(done0||err0||!ready0)$fatal(1,"Reset did not cancel pending completion");
  $display("TB_PASS P37 parser completion SCALE=%0d cases=%0d exact pixel sequence, original pre-edge verdict, +1 completion clock, errors and reset; pixel_checks=%0d",SCALE,cases,pixel_checks);
  $finish;
 end
 initial begin #2000000;$fatal(1,"Finish regression timeout");end
endmodule
