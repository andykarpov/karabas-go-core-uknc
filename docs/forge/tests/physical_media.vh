// Read-only physical 300 RPM / 250 kbit/s drive model. It presents a standard
// ten-sector UKNC track as flux pulses on the board pins, never SD requests.
wire [1:0] physical_ds;
wire physical_motor,physical_step,physical_dir,physical_side,physical_wgate,physical_wdata;
reg physical_flux=0,physical_index=0;
integer physical_track=5,physical_sectors=0,physical_words=0;
reg [7:0] physical_image[0:819199];
reg physical_present=0,physical_previous=0;
reg [15:0] physical_crc=16'hffff;
wire physical_track0=physical_track==0;
always @(posedge physical_step)begin
 if(physical_motor && physical_ds[0])begin
  if(physical_dir && physical_track<79)physical_track=physical_track+1;
  else if(!physical_dir && physical_track>0)physical_track=physical_track-1;
 end
end
always @(posedge ppuclk)if(physical_present && uut.ppu_wbm_ack_i_128 &&
 uut.ppu_wbm_stb_o && !uut.ppu_wbm_wre_o && uut.ppu_wbm_adr_o[1])physical_words=physical_words+1;
function [15:0] physical_crc8(input [15:0] c,input [7:0] d);
 integer k;reg [15:0] v;
 begin
  v=c^{d,8'd0};for(k=0;k<8;k=k+1)v=v[15]?(v<<1)^16'h1021:v<<1;
  physical_crc8=v;
 end
endfunction
task physical_cell(input bit b);
 begin
  physical_flux=b && physical_motor && physical_ds[0];#200;physical_flux=0;#1800;
 end
endtask
task physical_byte(input [7:0] value,input bit marker);
 integer k;reg c;
 begin
  physical_crc=physical_crc8(physical_crc,value);
  for(k=7;k>=0;k=k-1)begin
   c=!(physical_previous|value[k]);if(marker && value==8'ha1 && k==2)c=0;
   physical_cell(c);physical_cell(value[k]);physical_previous=value[k];
  end
 end
endtask
task physical_crc_bytes;
 reg [15:0] crc_copy;
 begin crc_copy=physical_crc;physical_byte(crc_copy[15:8],0);physical_byte(crc_copy[7:0],0);end
endtask
integer phys_s,phys_b,phys_lba,phys_c,phys_h;
initial forever begin
 wait(physical_present && physical_motor && physical_ds[0]);
 physical_index=1;
 repeat(110)physical_byte(8'h4e,0);
 physical_index=0;
 for(phys_s=1;phys_s<=10;phys_s=phys_s+1)begin
  phys_c=physical_track;phys_h=physical_side;
  phys_lba=(phys_c*2+phys_h)*10+phys_s-1;
  repeat(12)physical_byte(0,0);
  physical_crc=16'hffff;
  repeat(3)physical_byte(8'ha1,1);
  physical_byte(8'hfe,0);physical_byte(phys_c[7:0],0);physical_byte(phys_h[7:0],0);
  physical_byte(phys_s[7:0],0);physical_byte(2,0);physical_crc_bytes();
  repeat(22)physical_byte(8'h4e,0);repeat(12)physical_byte(0,0);
  physical_crc=16'hffff;
  repeat(3)physical_byte(8'ha1,1);physical_byte(8'hfb,0);
  for(phys_b=0;phys_b<512;phys_b=phys_b+1)physical_byte(physical_image[phys_lba*512+phys_b],0);
  physical_crc_bytes();repeat(40)physical_byte(8'h4e,0);
  physical_sectors=physical_sectors+1;
 end
end
