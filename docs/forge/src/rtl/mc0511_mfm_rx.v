// 250 kbit/s double-density MFM, 25 MHz sampling clock.
// GO input buffers invert the cable: a flux transition is a positive pulse.
// Recover 2 us channel cells, then align to the missing-clock A1 (4489).
module mc0511_mfm_rx(
 input wire clk, reset, flux,
 output reg [15:0] data=0,
 output reg valid=0, crc_ok=0
);
reg [5:0] phase=0;
reg seen=0;
reg [15:0] raw=0;
reg aligned=0, half_word=0;
reg [3:0] cells=0;
reg [7:0] high_byte=0;
reg [15:0] crc=16'hffff;
reg [4:0] marker_age=31;
wire [15:0] next_raw={raw[14:0],seen};
wire [7:0] byte_data={next_raw[14],next_raw[12],next_raw[10],next_raw[8],
                     next_raw[6],next_raw[4],next_raw[2],next_raw[0]};
function [15:0] crc_byte;
 input [15:0] c; input [7:0] d;
 integer i; reg [15:0] v;
 begin
  v=c;
  for(i=7;i>=0;i=i-1)v={v[14:0],1'b0} ^ ((v[15]^d[i])?16'h1021:16'd0);
  crc_byte=v;
 end
endfunction
always @(posedge clk)begin
 valid<=0;
 if(reset)begin
  phase<=0;seen<=0;raw<=0;aligned<=0;half_word<=0;cells<=0;
  high_byte<=0;crc<=16'hffff;crc_ok<=0;data<=0;marker_age<=31;
 end else begin
  // Re-centre on every transition; sample halfway to the next channel cell.
  if(flux)begin phase<=0;seen<=1;end
  else if(phase==49)phase<=0;
  else phase<=phase+1'b1;
  if(phase==24 && !flux)begin
   seen<=0;raw<=next_raw;
   if(marker_age!=31)marker_age<=marker_age+1'b1;
   if(next_raw==16'h4489)marker_age<=0;
   // Each address/data field starts a fresh CRC, even during continuous
   // track reads without another GDR command. Consecutive A1 bytes belong
   // to the same marker run and must all contribute to that CRC.
   if(next_raw==16'h4489 && (!aligned || marker_age>=16))begin
     aligned<=1;cells<=0;half_word<=1;high_byte<=8'ha1;
     crc<=crc_byte(16'hffff,8'ha1);crc_ok<=0;
   end else if(aligned)begin
    cells<=cells+1'b1;
    if(cells==15)begin
     crc<=crc_byte(crc,byte_data);
     half_word<=~half_word;
     if(half_word)begin
      data<={high_byte,byte_data};valid<=1;
      crc_ok<=crc_byte(crc,byte_data)==0;
     end else high_byte<=byte_data;
    end
   end
  end
 end
end
endmodule
