// VP1-128-style word buffer, MFM encoder and automatic CRC on underrun.
// Each 16-bit word takes 64 us. Outputs are active high at the GO FPGA.
module uknc_mfm_tx(
 input wire clk, reset, write_word, mark, restart_crc,
 input wire [15:0] data,
 output reg active=0, pulse=0, consumed=0, crc_out=0
);
reg pending=0, pending_mark=0, pending_restart=0, restart_armed=0;
reg [15:0] pending_data=0;
reg [31:0] shift=0;
reg [5:0] cells=0, phase=0;
reg [2:0] pulse_left=0;
reg previous=0, finishing=0;
reg [15:0] crc=16'hffff;
wire [15:0] next_data=pending?pending_data:data;
wire next_mark=pending?pending_mark:mark;
wire next_restart=pending?pending_restart:(restart_armed|restart_crc);
function [31:0] encode;
 input [15:0] d; input prev, marker;
 integer i; reg p; reg [31:0] v;
 begin
  p=prev;v=0;
  for(i=15;i>=0;i=i-1)begin
   v[2*i+1]=!(p|d[i]);v[2*i]=d[i];p=d[i];
  end
  if(marker && d[15:8]==8'ha1)v[31:16]=16'h4489;
  if(marker && d[7:0]==8'ha1)v[15:0]=16'h4489;
  encode=v;
 end
endfunction
function [15:0] crc_word;
 input [15:0] c,d;
 integer i; reg [15:0] v;
 begin
  v=c;
  for(i=15;i>=0;i=i-1)v={v[14:0],1'b0} ^ ((v[15]^d[i])?16'h1021:16'd0);
  crc_word=v;
 end
endfunction
always @(posedge clk)begin
 consumed<=0;
 if(reset)begin
  active<=0;pulse<=0;crc_out<=0;pending<=0;restart_armed<=0;
  shift<=0;cells<=0;phase<=0;pulse_left<=0;previous<=0;finishing<=0;crc<=16'hffff;
 end else begin
  if(restart_crc)restart_armed<=1;
  if(write_word)begin
   pending<=1;pending_data<=data;pending_mark<=mark;
   pending_restart<=restart_armed|restart_crc;restart_armed<=0;
  end
  if(pulse_left!=0)begin pulse_left<=pulse_left-1'b1;pulse<=1;end
  else pulse<=0;
  if(!active)begin
   phase<=0;
   if(pending || write_word)begin
    shift<=encode(next_data,1'b0,next_mark);cells<=32;
    crc<=crc_word(16'hffff,next_data);previous<=next_data[0];
    pending<=0;active<=1;consumed<=1;finishing<=0;crc_out<=0;
   end
  end else if(phase==49)begin
   phase<=0;
   if(cells!=0)begin
    pulse<=shift[31];pulse_left<=shift[31]?3'd4:3'd0;
    shift<={shift[30:0],1'b0};cells<=cells-1'b1;
   end else if(finishing)begin active<=0;end
   else if(pending || write_word)begin
    // Emit the next word's first cell on this boundary (no extra cell gap).
    pulse<=!(previous|next_data[15]);
    pulse_left<=!(previous|next_data[15])?3'd4:3'd0;
    shift<=encode(next_data,previous,next_mark)<<1;cells<=31;
    crc<=crc_word(next_restart?16'hffff:crc,next_data);
    previous<=next_data[0];pending<=0;consumed<=1;
   end else begin
    pulse<=!(previous|crc[15]);pulse_left<=!(previous|crc[15])?3'd4:3'd0;
    shift<=encode(crc,previous,1'b0)<<1;cells<=31;
    finishing<=1;crc_out<=1;
   end
  end else phase<=phase+1'b1;
 end
end
endmodule
