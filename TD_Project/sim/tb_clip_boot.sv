`timescale 1ns/1ps
// Scanner + validated sector adapter + fragmented file cursor + clip decoder +
// real write CDC. Raw card bytes are modelled; no physical card is written.
module tb_clip_boot;
 reg c=0,m=0,p=0,rst=0;always #5 c=~c;always #4 m=~m;always #20 p=~p;
 wire req;wire[31:0]lba;reg sv=0,se=0;reg[7:0]sb=0;
 wire we,full,idle,wr_reset,init,ready;wire[20:0]wa;wire[31:0]wd;wire[7:0]ce,error;
 wire nvalid,avalid,nactive,aactive;wire signed[15:0]ns,asample;
 wire vwe;wire[13:0]vwa;wire[7:0]vwd;integer voice_writes=0;
 integer normal_samples_checked=0,alert_samples_checked=0;
 function[15:0]expected_pcm(input integer n);
  expected_pcm={8'(n*2+1),8'(n*2)};
 endfunction
 always @(posedge p)if(rst)begin
  if(nvalid && dut.u_normal.u_wav.sample_counter!=0)begin
   if(ns!==expected_pcm(dut.u_normal.u_wav.sample_counter-1))$fatal(1,"normal PCM did not resume in order");
   normal_samples_checked++;
  end
  if(avalid && dut.u_alert.u_wav.sample_counter!=0)begin
   if(asample!==expected_pcm(dut.u_alert.u_wav.sample_counter-1))$fatal(1,"alert PCM did not resume in order");
   alert_samples_checked++;
  end
 end
 integer sample_cycle=0;always @(posedge p)sample_cycle<=sample_cycle+1;
 dual_fat32_pcm_source #(.ENABLE_CLIP(1),.SD_TIMEOUT_CYCLES(5000)) dut(
  .clk(c),.rst_n(rst),.enable(rst),.sd_read(req),.sd_lba(lba),.sd_valid(sv),.sd_byte(sb),.sd_end(se),
  .pix_clk(p),.pix_rst_n(rst),.sample_tick(sample_cycle%521==0),.normal_ready(1'b1),.alert_ready(1'b1),
  .normal_valid(nvalid),.alert_valid(avalid),.normal_sample(ns),.alert_sample(asample),
  .normal_active(nactive),.alert_active(aactive),.error(error),
  .clip_write_full(full),.clip_write_idle(idle),.clip_write_en(we),.clip_write_addr(wa),.clip_write_data(wd),
  .clip_write_reset(wr_reset),.clip_init_done(init),.clip_ready(ready),.clip_error(ce),
  .clip_voice_write_en(vwe),.clip_voice_write_addr(vwa),.clip_voice_write_data(vwd));
 wire aw,raw_idle;wire[20:0]aa;wire[31:0]ad;
 wire mem_reset;
 reset_sync rs(.clk(m),.ext_rst_n(rst && !wr_reset),.rst_n_sync(mem_reset));
 media_sdram_write_cdc cdc(.src_clk(c),.src_rst_n(rst && !wr_reset),
  .src_wr_en(we),.src_wr_addr(wa),.src_wr_mask(4'd0),.src_wr_data(wd),.src_full(full),.src_overflow(),
  .dst_clk(m),.dst_rst_n(mem_reset),.dst_app_wr_en(aw),.dst_app_wr_addr(aa),.dst_app_wr_mask(),.dst_app_wr_data(ad),.dst_idle(raw_idle));
 // As in four_bank_preload, wait for synchronization before accepting idle.
 sync_2ff si(.clk(c),.rst_n(rst),.async_in(raw_idle),.sync_out(idle));
 reg[7:0]asset[0:1552511];integer fault=0,writes=0,requests=0,burst=0,lastaddr=0;
 always @(negedge c)if(rst && vwe)begin
  if(vwa!=voice_writes || vwd!==asset[1536512+voice_writes] || init)$fatal(1,"voice preload/order/bounds");
  voice_writes++;
 end
 reg last_aw=0;
 always @(negedge m)if(rst)begin
  if(aw)begin:check_word
   integer off;
   off=aa-1228800;
   if(off!=writes || off>=384000)$fatal(1,"clip write address/order %h %0d",aa,writes);
   if(ad!=={8'd0,asset[512+off*4+2],asset[512+off*4+1],asset[512+off*4]})$fatal(1,"clip word data");
   if(init)$fatal(1,"image enabled before clip write drained");
   writes++;burst++;
  end
  if(last_aw && !aw)begin if(burst!=128)$fatal(1,"incomplete CDC burst %0d",burst);burst=0;end
  last_aw=aw;
 end
 localparam DS=16416,ROOT=DS+24;
 function[7:0]card_byte(input integer a,n);
  integer entry,f,cl,k,v,offset,id;
  reg[87:0]name;
  begin
   card_byte=0;
   if(a==0)case(n)
    0:card_byte='heb;12:card_byte=2;13:card_byte=8;14:card_byte=32;16:card_byte=2;
    32,33,34,35:card_byte=2000000>>((n-32)*8);
    36,37,38,39:card_byte=8192>>((n-36)*8);
    44:card_byte=5;510:card_byte='h55;511:card_byte='haa;
   endcase
   else if(a==ROOT)begin
    entry=n/32;f=n%32;cl=entry==0 ? 60000 : entry==1 ? 60003 : 100;
    name=entry==0 ? "AUDIO   PCM" : entry==1 ? "ALERT   PCM" : "CLIP    BIN";
    v=entry==2 ? (fault==5 ? 1552511 : 1552512) : 512;
    if(entry<3 && !(fault==1 && entry==2))begin
     if(f<11)card_byte=name>>((10-f)*8);
     case(f)
      11:card_byte='h20;
      20,21:card_byte=cl>>((f-18)*8);
      26,27:card_byte=cl>>((f-26)*8);
      28,29,30,31:card_byte=v>>((f-28)*8);
     endcase
    end
   end else if(a>=32 && a<8224)begin
    cl=(a-32)*128+n/4;v=0;
    if(cl==5 || cl==60000 || cl==60003)v=32'h0fffffff;
    k=(cl-100)/2;
    if(cl>=100 && cl==100+k*2 && k<380)v=k==379 ? 32'h0fffffff : cl+2;
    if(fault==4 && cl==100)v=32'h0fffffff;
    card_byte=v>>(8*(n%4));
   end else if(a>=DS)begin
    cl=(a-DS)/8+2;k=(cl-100)/2;
    if(cl>=100 && cl==100+k*2 && k<380)begin
     offset=(k*8+(a-DS)%8)*512+n;
     if(offset<1552512)begin
      card_byte=asset[offset];
      if(fault==2 && offset==512+7*4+3)card_byte=1;
      if(fault==3 && offset==20)card_byte=asset[offset]^1;
     end
    end else if(cl==60000 || cl==60003)card_byte=n;
   end
  end
 endfunction
 integer state=0,pos=0,address=0;
 always @(posedge c)begin
  if(!rst)begin state<=0;pos<=0;address<=0;sv<=0;se<=0;sb<=0;end
  else begin
   sv<=0;se<=0;
   case(state)
    0:if(req)begin address<=lba;pos<=0;state<=1;requests++;end
    1:begin
     sv<=1;sb<=card_byte(address,pos);
     if(pos==511)state<=2;else pos<=pos+1;
    end
    2:begin se<=1;state<=3;end
    3:if(!req)state<=4;
    4:state<=0;
   endcase
  end
 end
 task run_case(input integer f,expected_error,expected_words);
  begin
   @(negedge c);rst=0;repeat(10)@(negedge c);fault=f;writes=0;voice_writes=0;requests=0;last_aw=0;burst=0;
   normal_samples_checked=0;alert_samples_checked=0;rst=1;
   wait(init);repeat(20)@(negedge c);
   if(ce!==expected_error[7:0] || writes!=expected_words || ready!==(f==0))$fatal(1,"boot fault%0d ce%h writes%0d ready%b",f,ce,writes,ready);
   if(voice_writes!=((f==0 || f==3) ? 16000 : 0))$fatal(1,"voice sample count %0d",voice_writes);
   wait(normal_samples_checked>=16 && alert_samples_checked>=16);
   if(error!=0)$fatal(1,"background audio failed after preload %h",error);
   $display("CLIP_BOOT_PASS case%0d: writes%0d ready%b error%h sectors%0d, both audio streams resumed with 16 ordered PCM samples",f,writes,ready,ce,requests);
  end
 endtask
 initial begin
  $readmemh("clip_asset_bytes.hex",asset);
  run_case(0,0,384000);run_case(1,0,0);run_case(2,'hd4,0);run_case(3,'hd5,384000);
  run_case(4,'hd2,896);run_case(5,'hd1,0);
  $display("TB_PASS clip boot integration: actual asset, fragmented FAT32, scanner/adapter/CDC, exact 384000 writes and drain; optional missing, CRC and partial-burst abort fallback");$finish;
 end
 initial begin #150000000;$fatal(1,"timeout fault%0d state%0d ce%h",fault,dut.state,ce);end
endmodule
