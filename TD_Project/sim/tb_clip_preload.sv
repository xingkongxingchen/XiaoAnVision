`timescale 1ns/1ps
module tb_clip_preload;
 reg clk=0,rst=0,start=0;always #5 clk=~clk;
 reg valid=0,sdone=0,busy=0;reg[7:0]data=0,serr=0;reg[8:0]si=0;
 wire req,done,we;wire[31:0]lba,wd;wire[20:0]wa;wire[7:0]error;
 reg[7:0]bytes[0:1535];integer fault=0,writes=0,requests=0;
 reg[31:0]size=1536;
 clip_file_preloader #(.FRAME_WORDS(128),.FRAMES(2),.VOICE_SAMPLES(0)) dut(
  .clk(clk),.rst_n(rst),.start(start),.first_cluster(32'd5),.file_size(size),
  .fat_start(32'd10),.data_start(32'd100),.max_cluster(32'd100),.spc(8'd1),
  .sector_req(req),.sector_lba(lba),.sector_busy(busy),.sector_valid(valid),.sector_done(sdone),
  .sector_byte(data),.sector_error(serr),.sector_index(si),.write_full(1'b0),
  .write_en(we),.write_addr(wa),.write_data(wd),.done(done),.error(error));
 function[31:0]word_at(input integer n);
  word_at={8'd0,bytes[512+n*4+2],bytes[512+n*4+1],bytes[512+n*4]} ^ ((fault==2 && n==0) ? 32'h00000100 : 0);
 endfunction
 always @(negedge clk)if(rst && we)begin
  if(wa!=1228800+writes || wd!==word_at(writes))$fatal(1,"load order/data %0d wa%h wd%h",writes,wa,wd);
  writes++;
 end
 // Sector responder with deliberately fragmented FAT chain 5 -> 9 -> 10.
 initial forever begin
  wait(rst && req);@(negedge clk);busy=1;requests++;
  begin:respond
   integer a,n,value,idx;
   a=lba;
   repeat(3)@(negedge clk);
   for(n=0;n<512;n++)begin
    si=n;valid=1;value=0;
    if(a==10)begin
     if(n/4==5)value=fault==4 ? 32'h0fffffff : 9;
     if(n/4==9)value=10;
     if(n/4==10)value=32'h0fffffff;
     data=value>>(8*(n%4));
    end else begin
     idx=a==103 ? n : a==107 ? 512+n : a==108 ? 1024+n : -1;
     if(idx<0)$fatal(1,"unexpected sector %0d",a);
     data=bytes[idx];
     if(fault==1 && idx==4)data=0;
     if(fault==2 && idx==513)data=data^1;
     if(fault==3 && idx==515)data=1;
    end
    @(negedge clk);valid=0;@(negedge clk);
   end
   serr=fault==5 ? 8'h10 : 0;sdone=1;@(negedge clk);sdone=0;busy=0;
  end
 end
 task run_case(input integer f,expected);
  begin
   @(negedge clk);rst=0;repeat(4)@(negedge clk);fault=f;writes=0;size=f==6 ? 1535 : 1536;
   rst=1;repeat(3)@(negedge clk);start=1;@(negedge clk);start=0;
   wait(done);@(negedge clk);
   if(error!==expected[7:0])$fatal(1,"fault%0d actual%h expected%h",f,error,expected);
   if(f==0 && writes!=256)$fatal(1,"short good load %0d",writes);
   if((f==1 || f==6) && writes!=0)$fatal(1,"bad header/size wrote memory");
   $display("PRELOAD_CASE_PASS fault=%0d error=%h writes=%0d",f,error,writes);
   repeat(10)@(negedge clk);
  end
 endtask
 initial begin
  $readmemh("clip_fixture.hex",bytes);
  run_case(0,0);run_case(1,'hd3);run_case(2,'hd5);run_case(3,'hd4);
  run_case(4,'hd2);run_case(5,'hd2);run_case(6,'hd1);
  $display("TB_PASS fragmented clip FAT preload, exact memory bounds/order; header/CRC/padding/early-EOF/sector-error/size rejection");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
