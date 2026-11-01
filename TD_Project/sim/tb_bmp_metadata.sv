`timescale 1ns/1ps
module tb_bmp_metadata;
 reg clk=0,rst=1,start=0;always #5 clk=~clk;
 reg[31:0]id=0,c=5,z=512;reg[3:0]resources=15;
 wire[1:0]ready,error,rd,wr,pixel;wire[3:0]code[0:1];wire[31:0]addr[0:1];
 reference_bmp_metadata a(.clk(clk),.rst(rst),.load_start(start),.load_sector(id),.scan_start(1'b0),
  .sd_init_done(1'b1),.bmp_width(16'd640),.bmp_height(16'd480),.write_req_ack(1'b0),
  .sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0),
  .ready(ready[0]),.load_error(error[0]),.error_code(code[0]),.sd_sec_read(rd[0]),.sd_sec_read_addr(addr[0]),
  .write_req(wr[0]),.bmp_data_wr_en(pixel[0]),.load_done(),.sd_recover_reset(),.state_code(),
  .header_file_len(),.header_pixel_offset(),.timeout_trace(),.timeout_lba(),.bmp_data(),.bmp_top_down(),
  .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total());
 fat32_bmp_read b(.clk(clk),.rst(rst),.load_start(start),.load_sector(id),.scan_start(1'b0),
  .sd_init_done(1'b1),.bmp_width(16'd640),.bmp_height(16'd480),.write_req_ack(1'b0),
  .sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(1'b0),
  .ready(ready[1]),.load_error(error[1]),.error_code(code[1]),.sd_sec_read(rd[1]),.sd_sec_read_addr(addr[1]),
  .write_req(wr[1]),.bmp_data_wr_en(pixel[1]),.load_done(),.sd_recover_reset(),.state_code(),
  .header_file_len(),.header_pixel_offset(),.timeout_trace(),.timeout_lba(),.bmp_data(),.bmp_top_down(),
  .scan_done(),.scan_found_valid(),.scan_found_sector(),.scan_found_total());
 reg[1:0]previous_rd=0;
 integer cycle=0,cases=0,requests[0:1],req_time[0:1],err_time[0:1];reg[31:0]seen_addr[0:1];
 always @(posedge clk)begin
  cycle++;
  if(rst)previous_rd=0;
  else begin
   if(wr || pixel)$fatal(1,"pixel/write before header");
   for(integer j=0;j<2;j++)begin
    if(rd[j] && !previous_rd[j])begin requests[j]++;req_time[j]=cycle;seen_addr[j]=addr[j];end
    if(error[j] && err_time[j]<0)err_time[j]=cycle;
    previous_rd[j]=rd[j];
   end
  end
 end
 task run_case(input integer cluster,size,file_id,found,wiggle);
  bit ok;integer fs;
  begin
   @(negedge clk);rst=1;start=0;c=cluster;z=size;id=file_id;resources=found;
   requests[0]=0;requests[1]=0;err_time[0]=-1;err_time[1]=-1;
   repeat(5)@(negedge clk);rst=0;repeat(8)@(negedge clk);
   ok=file_id<=3 && found==15 && cluster>=2 && cluster<=64 && size>=54;
   fs=file_id>3 || found!=15 ? 'h22:'h24;
   start=1;@(negedge clk);start=0;
   if(wiggle)begin c=cluster==0?5:0;z=size==0?512:0;id=3;end
   repeat(24)@(negedge clk);
   if(ok)begin
    if(requests[0]!=1 || requests[1]!=1 || req_time[0]!=req_time[1] || err_time[0]>=0 || err_time[1]>=0 ||
       seen_addr[0]!==seen_addr[1] || seen_addr[1]!=1000+(cluster-2)*8)$fatal(1,"valid metadata changed case%0d",cases);
   end else begin
    if(requests[0]!=0 || requests[1]!=0 || err_time[0]<0 || err_time[1]<0 || code[0]!=9 || code[1]!=9 ||
       a.last_fs_error!=fs || b.last_fs_error!=fs)$fatal(1,"metadata rejection case%0d",cases);
    if(err_time[1]-err_time[0]!=(fs == 8'h24 ? 4 : 0))$fatal(1,"rejection latency case%0d",cases);
   end
   cases++;
  end
 endtask
 initial begin
  force a.resources=resources;force b.resources=resources;
  force a.c0=c;force a.c1=c;force a.c2=c;force a.c3=c;
  force b.c0=c;force b.c1=c;force b.c2=c;force b.c3=c;
  force a.z0=z;force a.z1=z;force a.z2=z;force a.z3=z;
  force b.z0=z;force b.z1=z;force b.z2=z;force b.z3=z;
  force a.max_cluster=64;force b.max_cluster=64;force a.spc=8;force b.spc=8;
  force a.data_lba=1000;force b.data_lba=1000;
  for(integer k=0;k<5;k++)for(integer j=0;j<4;j++)
   run_case(k==0?0:k==1?1:k==2?2:k==3?64:65,j==0?0:j==1?53:j==2?54:512,0,15,0);
  run_case(5,512,3,15,1);run_case(0,512,0,15,1);run_case(5,512,4,15,0);run_case(5,512,0,14,0);
  $display("TB_PASS captured BMP metadata: %0d cases; valid header address/timing unchanged; invalid metadata requests no sector and reports same errors four clocks later; ID/resource errors retain priority",cases);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
