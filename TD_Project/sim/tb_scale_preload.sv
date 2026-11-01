`timescale 1ns/1ps
// Real scanner/parser/resampler/loader/write CDC; only sector transport mocked.
module tb_scale_preload #(parameter FULL=0, DIAG=0);
 localparam H=FULL ? 480 : 16;
 reg clk=0,mclk=0,rst_n=0;
 always #5 clk=~clk;always #4 mclk=~mclk;
 wire ready,aw;wire[20:0]addr;wire[31:0]data;wire[3:0]mask,complete;
 wire[7:0]err;wire[3:0]state;wire[1:0]idx;
 wire[3:0]crc_checked;wire crc_fault,crc_protocol;wire[31:0]crc_actual;
 four_bank_preload #(.HEIGHT(H),.ENABLE_SCALE(1),.ENABLE_CRC_DIAG(DIAG)) dut(
 .diag_checked(crc_checked),.diag_fault(crc_fault),.diag_protocol_fault(crc_protocol),.diag_index(),.diag_actual(crc_actual),.diag_expected(),
 .clk(clk),.rst_n(rst_n),.mem_clk(mclk),.mem_rst_n(rst_n),.controller_busy(1'b0),
 .sd_ncs(),.sd_dclk(),.sd_mosi(),.sd_miso(1'b1),.app_wr_en(aw),.app_wr_addr(addr),
 .app_wr_data(data),.app_wr_mask(mask),.complete(complete),.ready(ready),.found(),
 .load_index(idx),.state(state),.error(err),.file_len(),.pixel_offset(),
 .timeout_trace(),.timeout_lba(),.boot_trace(),.boot_command(),.audio_sd_req(1'b0),.audio_sd_lba(32'd0),
 .audio_sd_ready(),.audio_sd_valid(),.audio_sd_end(),.audio_sd_byte());
 integer writes[0:3],bank,offset,x,y,sx,sy,total=0,burst=0;
 reg lastaw=0;reg[23:0]expected;
 always @(negedge clk)if(rst_n && ready !== (state==9))
  $fatal(1,"latched ready differs from original DONE state predicate");
 // At actual HCHECK the cached predicate must equal the original live one.
 always @(negedge clk)if(rst_n && dut.u_parser.state==5)begin
  if(dut.u_parser.dimensions_ok!==
    (dut.u_parser.width>=1 && dut.u_parser.width<=1920 &&
     dut.u_parser.absolute_height>=1 && dut.u_parser.absolute_height<=1080))
   $fatal(1,"cached dimensions not settled at complete header check");
  if(dut.u_parser.bounds_ok!==
    (dut.u_parser.offset>=54 && dut.u_parser.offset<dut.u_parser.file_len &&
     dut.u_parser.file_len<=dut.u_parser.selected_size &&
     dut.u_parser.pixel_end<={3'd0,dut.u_parser.file_len}))
   $fatal(1,"cached bounds not settled at complete header check");
 end
 always @(negedge mclk)if(rst_n)begin
  if(aw)begin
   if(addr>=4*640*H || mask!=0 || ready)$fatal(1,"address/ownership error");
   bank=addr/(640*H);offset=addr%(640*H);x=offset%640;y=offset/640;
   sx=x*dut.u_sd.sw(bank)/640;sy=y*dut.u_sd.sh(bank)/H;
   expected={8'((sx^sy)+bank*17),8'(sy),8'(sx)};
   if(data!=={8'd0,expected})$fatal(1,"bank%0d addr%0d got%h expected%h",bank,addr,data,expected);
   if(offset!=((bank%2) ? writes[bank] : (H-1-writes[bank]/640)*640+writes[bank]%640))
     $fatal(1,"row orientation/order");
   writes[bank]++;total++;burst++;
  end
  if(lastaw && !aw)begin if(burst!=128)$fatal(1,"split burst %d",burst);burst=0;end
  lastaw=aw;
 end
 initial begin
  for(integer i=0;i<4;i++)writes[i]=0;
  dut.u_sd.full_size=FULL;dut.u_sd.spc=8;
  repeat(10)@(negedge clk);rst_n=1;
  wait(ready || err!=0);repeat(20)@(negedge clk);
  if(err!=0 || complete!=15 || total!=4*640*H)$fatal(1,"preload error %h state%h bank%d total%d",err,state,idx,total);
  for(integer i=0;i<4;i++)if(writes[i]!=640*H)$fatal(1,"bank count");
  if(DIAG && (crc_checked!=1 || !crc_fault || crc_protocol || crc_actual!=32'h000071fa))$fatal(1,"source CRC integration first-fault capture/protocol");
  if(DIAG)$display("SOURCE_PROBE_PASS first actual CRC=%h (synthetic assets intentionally differ from R4)",crc_actual);
  $display("PRELOAD_PASS four mixed resolutions bottom/top down, all pixels, %d writes",total);
  // Fail malformed dimensions before the first SDRAM write.
  rst_n=0;repeat(10)@(negedge clk);dut.u_sd.invalid_dimensions=1;rst_n=1;
  wait(err!=0 || ready);
  if(err!=8'h11 || ready || total!=4*640*H)$fatal(1,"invalid dimensions not rejected %h",err);
  $display("TB_PASS scale FAT32/preload/CDC integration FULL=%d and dimension rejection",FULL);$finish;
 end
 initial begin #2000000000;$fatal(1,"timeout state %h error %h",state,err);end
endmodule
