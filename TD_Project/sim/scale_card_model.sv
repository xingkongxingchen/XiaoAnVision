`timescale 1ns/1ps
// Sparse FAT32 disk model: MBR or superfloppy, PIC names out of directory order,
// directory entries in root sector 2; file clusters deliberately skip every other cluster.
module sd_card_top #(parameter SPI_LOW_SPEED_DIV=248, SPI_HIGH_SPEED_DIV=0)(
 input clk,rst,SD_MISO,output SD_nCS,SD_DCLK,SD_MOSI,
 output reg sd_init_done,input sd_sec_read,input[31:0]sd_sec_read_addr,
 output reg[7:0]sd_sec_read_data,output reg sd_sec_read_data_valid,sd_sec_read_end,
 input sd_sec_write,input[31:0]sd_sec_write_addr,input[7:0]sd_sec_write_data,
 output sd_sec_write_data_req,sd_sec_write_end,
 output[31:0]debug_command,output[7:0]debug_status
);
 integer w=4,h=100,spc=2,part=2048;
 integer fault=0,missing=0,bad_header=0,short_remaining=0,stall_remaining=0;
 integer state=0,pos=0,requests=0;
 integer boot_fault=0,early_dir_end=0;
 integer audio_present=0,audio_size=16384,audio_fault=0;
 reg[31:0]address;
 reg stall,short_read;
 localparam RESERVED=32,FATSZ=8192,TOTAL=2000000;
 integer full_size=0,invalid_dimensions=0;
 function integer sw(input integer id);
  if(invalid_dimensions)sw=1921;
  else case(id)0:sw=320;1:sw=800;2:sw=1024;3:sw=641;endcase
 endfunction
 function integer sh(input integer id);
  if(full_size)case(id)0:sh=240;1:sh=600;2:sh=768;3:sh=479;endcase
  else case(id)0:sh=8;1:sh=20;2:sh=26;3:sh=17;endcase
 endfunction
 function integer fsize(input integer id);
  fsize=54+((sw(id)*3+3)&~3)*sh(id);
 endfunction
 wire[31:0]data_start=part+RESERVED+2*FATSZ;
 assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=1;
 assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
 assign debug_command=32'h10060005;assign debug_status=8'h09;
 function[31:0]first;
  input integer id;begin first=10+id*10000;end
 endfunction
 function[7:0]file_byte;
  input integer id,offset;
  integer n,stride,p,x,y,signed_h;
  begin
   n=fsize(id);stride=(sw(id)*3+3)&~3;
   signed_h=id%2 ? -sh(id) : sh(id);
   file_byte=0;
   case(offset)
    0:file_byte=(bad_header==id+1) ? 0 : "B";1:file_byte="M";
    2,3,4,5:file_byte=n>>((offset-2)*8);
    10:file_byte=54;14:file_byte=40;
    18,19,20,21:file_byte=sw(id)>>((offset-18)*8);
    22,23,24,25:file_byte=signed_h>>((offset-22)*8);
    26:file_byte=1;28:file_byte=24;
    default:if(offset>=54 && offset<n)begin
     p=offset-54;x=(p%stride)/3;y=p/stride;
     if(id%2==0)y=sh(id)-1-y;
     if(p%stride>=sw(id)*3)file_byte=8'hec;
     else case(p%stride%3)
      0:file_byte=x;1:file_byte=y;2:file_byte=(x^y)+id*17;
     endcase
    end
   endcase
  end
 endfunction
 function[7:0]byte_at;
  input[31:0]a;input integer p;
  integer cl,id,k,idx,n,cnum,entry,field,value,logical_sector;
  begin
   byte_at=0;n=54+w*h*3;cnum=(n+512*spc-1)/(512*spc);
   if(part!=0 && a==0)begin
    case(p)
     450:byte_at=8'h0c;
     454,455,456,457:byte_at=part>>((p-454)*8);
     458,459,460,461:byte_at=TOTAL>>((p-458)*8);
     510:byte_at=8'h55;511:byte_at=8'haa;
    endcase
   end else if(a==part)begin
    case(p)
     0:byte_at=8'heb;11:byte_at=0;12:byte_at=2;13:byte_at=spc;
     14:byte_at=RESERVED;16:byte_at=2;
     32,33,34,35:byte_at=TOTAL>>((p-32)*8);
     36,37,38,39:byte_at=FATSZ>>((p-36)*8);
     44:byte_at=5;
     510:byte_at=8'h55;511:byte_at=8'haa;
    endcase
   end else if(a>=part+RESERVED && a<part+RESERVED+FATSZ)begin
    cl=(a-part-RESERVED)*128+p/4;value=0;
    if(cl==5)value=32'h0fffffff;
    for(id=0;id<4;id=id+1)begin
     cnum=(fsize(id)+512*spc-1)/(512*spc);
     k=(cl-first(id))/2;
     if(cl>=first(id) && cl-first(id)==k*2 && k<cnum)begin
      value=(k==cnum-1) ? 32'h0fffffff : cl+2;
      if(id==1 && fault!=0)case(fault)
       1:value=32'h0fffffff; // premature EOF
       2:value=cl;          // self loop
       3:value=1;           // reserved/out of range
      endcase
     end
    end
    byte_at=value>>(8*(p%4));
   end else if(a==data_start+(5-2)*spc)begin
    // Occupied/deleted entries, not end-of-directory; PIC entries are later.
    if(p%32==0)byte_at=8'he5;
   end else if(a==data_start+(5-2)*spc+1)begin
    entry=p/32;field=p%32;id=-1;
    case(entry)3:id=2;7:id=0;10:id=3;14:id=1;endcase
    if(id<0 || missing==id+1)begin if(field==0)byte_at=entry==15 ? 0 : 8'he5;end
    else case(field)
     0:byte_at="P";1:byte_at="I";2:byte_at="C";3:byte_at="1"+id;
     4,5,6,7:byte_at=" ";8:byte_at="B";9:byte_at="M";10:byte_at="P";
     11:byte_at=8'h21; // ordinary file with archive+read-only flags
     20:byte_at=first(id)>>16;21:byte_at=first(id)>>24;
     26:byte_at=first(id);27:byte_at=first(id)>>8;
     28,29,30,31:byte_at=fsize(id)>>((field-28)*8);
    endcase
   end else if(a>=data_start)begin
    cl=(a-data_start)/spc+2;
    for(id=0;id<4;id=id+1)begin
     cnum=(fsize(id)+512*spc-1)/(512*spc);
     k=(cl-first(id))/2;
     if(cl>=first(id) && cl-first(id)==k*2 && k<cnum)begin
      logical_sector=k*spc+(a-data_start)%spc;
      byte_at=file_byte(id,logical_sector*512+p);
     end
    end
   end
   if(audio_present)begin
    if(a==data_start+(5-2)*spc+1 && p/32==2)begin
     byte_at=0;
     case(p%32)
      0:byte_at="A";1:byte_at="U";2:byte_at="D";3:byte_at="I";4:byte_at="O";
      5,6,7:byte_at=" ";8:byte_at="P";9:byte_at="C";10:byte_at="M";11:byte_at=8'h20;
      26:byte_at=60000%256;27:byte_at=60000/256;
      28,29,30,31:byte_at=audio_size>>(((p%32)-28)*8);
     endcase
    end
    if(a>=part+RESERVED && a<part+RESERVED+FATSZ)begin
     cl=(a-part-RESERVED)*128+p/4;k=(cl-60000)/3;
     if(cl>=60000 && cl==60000+k*3 && k<(audio_size+spc*512-1)/(spc*512))begin
      value=((k+1)*spc*512>=audio_size || audio_fault==1) ? 32'h0fffffff : cl+3;
      byte_at=value>>(8*(p%4));
     end
    end else if(a>=data_start)begin
     cl=(a-data_start)/spc+2;k=(cl-60000)/3;
     if(cl>=60000 && cl==60000+k*3 && k<(audio_size+spc*512-1)/(spc*512))begin
      logical_sector=k*spc+(a-data_start)%spc;
      value=((logical_sector*256+p/2)*73+4096)&65535;
      byte_at=value>>(8*(p%2));
     end
    end
   end
   if(a==part)begin
    if(boot_fault==1 && p==511)byte_at=0;
    if(boot_fault==2 && p==13)byte_at=3;
    if(boot_fault==3 && p==40)byte_at=8'h81;
    if(boot_fault==4 && p>=36 && p<=39)byte_at=8'hff;
    if(boot_fault==5 && p>=44 && p<=47)byte_at=8'hff;
   end
   if(early_dir_end && a==data_start+(5-2)*spc && p==0)byte_at=0;
  end
 endfunction
 initial if($test$plusargs("FULL"))begin w=640;h=480;spc=8;end
 always @(posedge clk)begin
  if(rst)begin
   sd_init_done<=0;state<=0;pos<=0;address<=0;stall<=0;short_read<=0;
   sd_sec_read_data<=0;sd_sec_read_data_valid<=0;sd_sec_read_end<=0;
  end else begin
   sd_init_done<=1;sd_sec_read_data_valid<=0;sd_sec_read_end<=0;
   if(sd_sec_write)$fatal(1,"FAT32 reader attempted card write");
   case(state)
    0:if(sd_sec_read)begin
     address<=sd_sec_read_addr;pos<=0;state<=1;requests<=requests+1;
     short_read<=short_remaining>0;stall<=stall_remaining>0;
     if(short_remaining>0)short_remaining<=short_remaining-1;
     if(stall_remaining>0)stall_remaining<=stall_remaining-1;
    end
    1:if(!(stall && pos==60))begin
     sd_sec_read_data<=byte_at(address,pos);sd_sec_read_data_valid<=1;
     if(pos==(short_read ? 59 : 511))state<=2;else pos<=pos+1;
    end
    2:begin sd_sec_read_end<=1;state<=3;end
    3:if(!sd_sec_read)state<=4;
    4:state<=0;
   endcase
  end
 end
endmodule
