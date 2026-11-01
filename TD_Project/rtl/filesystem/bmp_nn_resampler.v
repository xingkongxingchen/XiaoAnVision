`timescale 1ns/1ps
// MiCu lesson 13 nearest-neighbour mapping, applied before the resident banks.
// One source line + a sector skid buffer; no frame-sized on-chip storage.
// Sector requests must be held while sector_pause is high. An in-flight 512
// byte sector always drains; the 256-byte threshold leaves ample headroom.
module bmp_nn_resampler #(
 parameter integer PIXEL_INTERVAL=64
)(
 input wire clk,rst,start,
 input wire [10:0] source_width,source_height,dest_width,dest_height,
 input wire top_down,input wire[31:0]pixel_offset,
 input wire file_valid,input wire[7:0]file_byte,input wire file_done,
 output wire sector_pause,output reg done,error,
 output reg pixel_valid,output reg[23:0]pixel_rgb
);
 localparam IDLE=0,INIT_Y=1,READ=2,CHECK_ROW=3,FETCH=4,WAIT_RAM=5,
            SEND=6,ADV_X=7,ADV_Y=8,DRAIN=9;
 reg[3:0]state;
 reg[7:0]byte_mem[0:1023] /* fehdl force_ram=1, ram_style="bram" */;
 reg[23:0]line_mem[0:2047] /* fehdl force_ram=1, ram_style="bram" */;
 reg[9:0]wr_ptr,rd_ptr;
 reg[10:0]count;
 reg[7:0]byte_q;
 reg pending,held,end_seen;
 reg[31:0]byte_offset;
 reg[12:0]row_byte;
 reg[10:0]input_x,file_row,target_y,dest_y,dest_x,source_x;
 reg[12:0]x_remainder,y_remainder;
 reg[1:0]channel;
 reg[7:0]blue,green;
 reg[23:0]line_q;
 reg[7:0]pace;
 reg[12:0]row_rgb_bytes,row_last_byte;
 wire[12:0]row_stride=(row_rgb_bytes+13'd3)&13'h1ffc;
 wire push=file_valid && !done && !error;
 wire pop=count!=0 && !pending && !held && state!=IDLE;
 wire take=held && (state==READ || state==DRAIN);
 wire line_write=take && state==READ && byte_offset>=pixel_offset &&
                 row_byte<row_rgb_bytes && channel==2;
 assign sector_pause=count>256 || error;
 // Reset only pointers, not RAM contents; synchronous ports infer block RAM.
 always @(posedge clk)begin
  if(push && count<1024)byte_mem[wr_ptr]<=file_byte;
  if(pop)byte_q<=byte_mem[rd_ptr];
  if(line_write)line_mem[input_x]<={byte_q,green,blue};
  if(state==FETCH)line_q<=line_mem[source_x];
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;wr_ptr<=0;rd_ptr<=0;count<=0;pending<=0;held<=0;
   end_seen<=0;done<=0;error<=0;pixel_valid<=0;pixel_rgb<=0;
   byte_offset<=0;row_byte<=0;input_x<=0;file_row<=0;target_y<=0;
   dest_y<=0;dest_x<=0;source_x<=0;x_remainder<=0;y_remainder<=0;
   channel<=0;blue<=0;green<=0;pace<=0;
   row_rgb_bytes<=0;row_last_byte<=0;
  end else if(start)begin
   state<=INIT_Y;wr_ptr<=0;rd_ptr<=0;count<=0;pending<=0;held<=0;
   end_seen<=0;done<=0;error<=0;pixel_valid<=0;
   byte_offset<=0;row_byte<=0;input_x<=0;file_row<=0;target_y<=0;
   dest_y<=0;dest_x<=0;source_x<=0;x_remainder<=0;
   // Reverse the top-origin floor mapping for a bottom-up BMP:
   // file_row = ceil((dest_file_row+1)*source_height/dest_height)-1.
   y_remainder<=top_down ? 13'd0 : {2'd0,source_height}-1'b1;
   channel<=0;pace<=0;
   // Geometry is constant for this start-to-done transaction. Stage the
   // stride arithmetic before READ instead of feeding its byte-state mux.
   row_rgb_bytes<={1'b0,source_width,1'b0}+{2'd0,source_width};
  end else begin
   pixel_valid<=0;
   if(pace!=0)pace<=pace-1'b1;
   if(file_done)end_seen<=1;
   if(push)begin
    if(count==1024)error<=1;
    else wr_ptr<=wr_ptr+1'b1;
   end
   if(pop)begin rd_ptr<=rd_ptr+1'b1;pending<=1;end
   if(pending)begin pending<=0;held<=1;end
   if(take)begin held<=0;byte_offset<=byte_offset+1'b1;end
   case({push && count<1024,pop})
    2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:;
   endcase
   case(state)
    INIT_Y:begin
     row_last_byte<=row_stride-1'b1;
     if(y_remainder>=dest_height)begin
      y_remainder<=y_remainder-dest_height;target_y<=target_y+1'b1;
     end else state<=READ;
    end
    READ:if(take && byte_offset>=pixel_offset)begin
     if(row_byte<row_rgb_bytes)case(channel)
      0:begin blue<=byte_q;channel<=1;end
      1:begin green<=byte_q;channel<=2;end
      2:begin input_x<=input_x+1'b1;channel<=0;end
     endcase
     if(row_byte==row_last_byte)begin
      row_byte<=0;input_x<=0;channel<=0;state<=CHECK_ROW;
     end else row_byte<=row_byte+1'b1;
    end
    CHECK_ROW:if(file_row==target_y)begin
      dest_x<=0;source_x<=0;x_remainder<=0;state<=FETCH;
     end else begin file_row<=file_row+1'b1;state<=READ;end
    FETCH:state<=WAIT_RAM;
    WAIT_RAM:state<=SEND;
    SEND:if(pace==0)begin
     pixel_rgb<=line_q;pixel_valid<=1;pace<=PIXEL_INTERVAL-1;
     if(dest_x==dest_width-1'b1)begin
      if(dest_y==dest_height-1'b1)state<=DRAIN;
      else begin dest_y<=dest_y+1'b1;y_remainder<=y_remainder+source_height;state<=ADV_Y;end
     end else begin
      dest_x<=dest_x+1'b1;x_remainder<=x_remainder+source_width;state<=ADV_X;
     end
    end
    ADV_X:if(x_remainder>=dest_width)begin
      x_remainder<=x_remainder-dest_width;source_x<=source_x+1'b1;
     end else state<=FETCH;
    ADV_Y:if(y_remainder>=dest_height)begin
      y_remainder<=y_remainder-dest_height;target_y<=target_y+1'b1;
     end else state<=CHECK_ROW;
    default:;
   endcase
   // File completion may precede the final duplicated/scaled rows. Commit
   // only after scaling AND every queued byte have drained (including tail).
   if(end_seen && count==0 && !held && !pending && !file_valid)begin
    if(state==DRAIN)begin done<=1;state<=IDLE;end
    else if(state==READ)begin error<=1;state<=IDLE;end
   end
  end
 end
endmodule
