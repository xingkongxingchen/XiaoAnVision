`timescale 1ns/1ps
module tb_adapter_equivalence;
 reg clk=0,rst=1,enable=0,req=0,valid=0,ending=0;
 reg[31:0]lba=0;reg[7:0]data=0;
 always #5 clk=~clk;
 wire[1:0]busy,out_valid,done,read_req;
 wire[7:0]out_byte[0:1],error[0:1];wire[8:0]index[0:1];wire[31:0]addr[0:1];
 sd_sector_adapter #(.TIMEOUT_CYCLES(1200)) dut(.clk(clk),.rst(rst),.enable(enable),.sector_req(req),.sector_lba(lba),
  .sector_busy(busy[0]),.sector_valid(out_valid[0]),.sector_byte(out_byte[0]),.sector_byte_index(index[0]),
  .sector_done(done[0]),.sector_error(error[0]),.sd_sec_read(read_req[0]),.sd_sec_read_addr(addr[0]),
  .sd_sec_read_data_valid(valid),.sd_sec_read_data(data),.sd_sec_read_end(ending));
 reference_sd_sector_adapter #(.TIMEOUT_CYCLES(1200)) ref_dut(.clk(clk),.rst(rst),.enable(enable),.sector_req(req),.sector_lba(lba),
  .sector_busy(busy[1]),.sector_valid(out_valid[1]),.sector_byte(out_byte[1]),.sector_byte_index(index[1]),
  .sector_done(done[1]),.sector_error(error[1]),.sd_sec_read(read_req[1]),.sd_sec_read_addr(addr[1]),
  .sd_sec_read_data_valid(valid),.sd_sec_read_data(data),.sd_sec_read_end(ending));
 integer checks=0,bytes_seen=0,cases=0,seed=32'h44261026;
 always @(negedge clk)if(!rst)begin
  if({busy[0],out_valid[0],out_byte[0],index[0],done[0],error[0],read_req[0],addr[0]} !==
     {busy[1],out_valid[1],out_byte[1],index[1],done[1],error[1],read_req[1],addr[1]})
   $fatal(1,"adapter interface mismatch case=%0d index=%0d valid=%b/%b",cases,index[0],out_valid[0],out_valid[1]);
  if(dut.emit_ready !== (dut.busy && dut.count<512))$fatal(1,"predicate invariant failed");
  checks=checks+1;if(out_valid[0])bytes_seen=bytes_seen+1;
 end
 task tick;begin @(posedge clk);#1;end endtask
 task start_sector;
  begin wait(!busy[0]&&!busy[1]);#2;req=1;lba=lba+17;tick();req=0;wait(&read_req);end
 endtask
 task sector(input integer length,input bit final_same,input bit gaps,input bit drop_enable);
  begin
   start_sector();
   for(integer i=0;i<length;i=i+1)begin
    #1;valid=1;data=8'(i^cases);ending=final_same&&i==length-1;
    if(drop_enable&&i==23)enable=0;
    tick();valid=0;ending=0;
    if(gaps&&i%7==0)tick();
   end
   if(!final_same)begin tick();ending=1;tick();ending=0;end
   repeat(7)tick();enable=1;cases=cases+1;
  end
 endtask
 initial begin
  repeat(4)tick();rst=0;enable=1;
  sector(512,1,0,0);sector(512,0,1,0);sector(511,1,0,0);
  sector(513,1,0,0);sector(1025,0,0,0);sector(0,0,0,0);
  sector(512,1,0,1);
  // Timeout, including external valid on the expiry boundary.
  start_sector();repeat(1199)tick();valid=1;data=8'hab;tick();valid=0;repeat(8)tick();cases=cases+1;
  // Abort while receiving and recover on a new full sector.
  start_sector();valid=1;repeat(32)tick();rst=1;tick();valid=0;ending=0;req=0;rst=0;cases=cases+1;
  sector(512,1,0,0);
  for(integer i=0;i<20000;i=i+1)begin
   #1;
   if(($random(seed)&255)==0)rst=1;else rst=0;
   enable=($random(seed)&7)!=0;req=($random(seed)&15)==0;
   valid=($random(seed)&3)!=0;ending=($random(seed)&63)==0;
   data=$random(seed);lba=$random(seed);tick();
  end
  rst=1;tick();rst=0;enable=1;req=0;valid=0;ending=0;
  sector(512,1,0,0);repeat(4)tick();
  if(checks<20000||bytes_seen<2000)$fatal(1,"insufficient coverage");
  $display("TB_PASS P44 adapter cycle-equivalent: checks=%0d cases=%0d bytes=%0d full/short/long/gaps/end/timeout/reset/enable/random",checks,cases,bytes_seen);
  $finish;
 end
 initial begin #10000000;$fatal(1,"adapter equivalence timeout");end
endmodule
