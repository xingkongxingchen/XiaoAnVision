`timescale 1ns/1ps
module sector_model(input clk,rst,req,input[31:0]lba,input integer mode,
 output reg busy=0,valid=0,done=0,output reg[7:0]data=0,error=0,output reg[8:0]index=0);
 integer n=0,t=0;reg[31:0]a;
 function[7:0]value(input integer offset);
  reg[31:0]entry;integer cluster;
  begin
   value=(a*7+offset*3)&255;
   if(a==100)begin
    cluster=offset/4;
    case(cluster)
     5:entry=mode==5 ? 5 : mode==6 ? 28'hffffff8 : mode==7 ? 66 : 9;
     9:entry=mode==4 ? 28'hffffff8 : 10;
     10:entry=mode==8 ? 11 : 28'hffffff8;
     default:entry=28'hffffff8;
    endcase
    value=entry>>((offset%4)*8);
   end
  end
 endfunction
 always @(posedge clk)begin
  if(!rst)begin busy<=0;valid<=0;done<=0;error<=0;n=0;t=0;end
  else begin
   valid<=0;done<=0;
   if(req&&!busy)begin busy<=1;a=lba;n=0;t=0;error<=0;end
   else if(busy)begin
    t++;
    if(n==512)begin busy<=0;done<=1;error<=mode==10&&a==100 ? 1:0;end
    else if(t%3!=0)begin valid<=1;index<=n;data<=value(n);n++;end
   end
  end
 end
endmodule
module tb_file_stream_equivalence;
 reg clk=0,rst=0,start=0;always #5 clk=~clk;
 reg[31:0]first=5,size=1536;reg[7:0]spc=1;integer mode=0;
 wire[1:0]req,busy,sv,sd,done,fv;wire[31:0]lba[0:1],offset[0:1];
 wire[7:0]sb[0:1],se[0:1],fb[0:1],fe[0:1];wire[8:0]si[0:1];
 reference_file_streamer #(.MAX_VISITED_CLUSTERS(3)) a(
  .clk(clk),.rst_n(rst),.file_start(start),.first_cluster(first),.file_size(size),.sectors_per_cluster(spc),
  .fat_start_lba(32'd100),.data_start_lba(32'd1000),.max_cluster(32'd64),.file_busy(),.file_done(done[0]),
  .file_valid(fv[0]),.file_byte(fb[0]),.file_byte_offset(offset[0]),.fs_error(fe[0]),
  .sector_req(req[0]),.sector_lba(lba[0]),.sector_busy(busy[0]),.sector_valid(sv[0]),
  .sector_byte(sb[0]),.sector_byte_index(si[0]),.sector_done(sd[0]),.sector_error(se[0]));
 fat32_file_streamer #(.MAX_VISITED_CLUSTERS(3)) b(
  .clk(clk),.rst_n(rst),.file_start(start),.first_cluster(first),.file_size(size),.sectors_per_cluster(spc),
  .fat_start_lba(32'd100),.data_start_lba(32'd1000),.max_cluster(32'd64),.file_busy(),.file_done(done[1]),
  .file_valid(fv[1]),.file_byte(fb[1]),.file_byte_offset(offset[1]),.fs_error(fe[1]),
  .sector_req(req[1]),.sector_lba(lba[1]),.sector_busy(busy[1]),.sector_valid(sv[1]),
  .sector_byte(sb[1]),.sector_byte_index(si[1]),.sector_done(sd[1]),.sector_error(se[1]));
 for(genvar g=0;g<2;g++)begin
  sector_model m(clk,rst,req[g],lba[g],mode,busy[g],sv[g],sd[g],sb[g],se[g],si[g]);
 end
 integer bytes[0:1],requests[0:1],end_cycle[0:1],cycle=0,cases=0,total_bytes=0;
 reg[1:0]finished=0;
 reg[39:0]observed[0:1][0:4095];reg[31:0]addresses[0:1][0:31];
 always @(posedge clk)begin
  cycle++;
  if(rst)for(integer j=0;j<2;j++)begin
   if(req[j])begin addresses[j][requests[j]]=lba[j];requests[j]++;end
   if(fv[j])begin observed[j][bytes[j]]={offset[j],fb[j]};bytes[j]++;end
   if(done[j])begin finished[j]=1;end_cycle[j]=cycle;end
  end
 end
 task run_case(input integer m,fs,fc,s,err,delta);
  begin
   @(negedge clk);rst=0;start=0;mode=m;size=fs;first=fc;spc=s;finished=0;
   bytes[0]=0;bytes[1]=0;requests[0]=0;requests[1]=0;
   repeat(4)@(negedge clk);rst=1;start=1;@(negedge clk);start=0;
   wait(finished==3);@(negedge clk);
   if(fe[0]!=err || fe[1]!=err || bytes[0]!=bytes[1] || requests[0]!=requests[1])$fatal(1,"result differs case%0d e%h/%h b%0d/%0d",m,fe[0],fe[1],bytes[0],bytes[1]);
   for(integer k=0;k<bytes[0];k++)if(observed[0][k]!==observed[1][k])$fatal(1,"byte differs case%0d n%0d",m,k);
   for(integer k=0;k<requests[0];k++)if(addresses[0][k]!==addresses[1][k])$fatal(1,"request differs case%0d n%0d",m,k);
   if(end_cycle[1]-end_cycle[0]!=delta)$fatal(1,"unexpected latency case%0d delta%0d wanted%0d",m,end_cycle[1]-end_cycle[0],delta);
   cases++;total_bytes+=bytes[0];$display("FILE_EQ_CASE %0d bytes%0d requests%0d error%h added_cycles%0d",m,bytes[0],requests[0],fe[1],delta);
  end
 endtask
 initial begin
  run_case(0,0,5,1,0,0);run_case(1,512,0,1,'h24,0);run_case(2,512,5,0,'h24,0);
  run_case(3,1536,5,1,0,2);run_case(4,2600,5,4,0,1);
  run_case(5,1024,5,1,'h23,0);run_case(6,1024,5,1,'h25,0);
  run_case(7,1024,5,1,'h24,0);run_case(8,2048,5,1,'h26,2);
  run_case(9,512,5,1,'h23,0);run_case(10,1024,5,1,'h10,0);
  run_case(11,1300,5,1,0,2);
  $display("TB_PASS file cursor transaction equivalence: %0d cases %0d bytes; fragmented/SPC/partial/zero files, range/self-loop/EOF/visited/sector errors; one added clock per valid cluster advance",cases,total_bytes);$finish;
 end
 initial begin #2000000;$fatal(1,"equivalence timeout case%0d",mode);end
endmodule
