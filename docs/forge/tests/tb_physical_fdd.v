`timescale 1ns/1ps
module tb_physical_fdd;
reg clk=0;always #20 clk=~clk;
reg pclk=0;always #160 pclk=~pclk;
reg reset=1,en=1;reg [2:0] mapping=0;
reg [16:0] adr=0;reg [15:0] din=0;reg stb=0,we=0;
wire ack;wire [15:0] image_dout,physical_dout;
wire [1:0] drive;wire motor,step,dir,head;
reg [3:0] wp=0;
wire selected=mapping>=1 && mapping<=4 && {1'b0,drive}==mapping-1;
wire [15:0] dout=selected?physical_dout:image_dout;
wire [1:0] ds;wire mot,st,di,side,wg,wd;
reg idx=0,tr0=1,protect=0,flux=0;
vp1_128fdd controller(.ppu_vm_clk_p(pclk),.ppu_vm_init_i(reset),
 .ppu_wbm_adr_i(adr),.ppu_wbm_dat_i(din),.ppu_wbm_dat_o(image_dout),
 .ppu_wbm_cyc_i(stb),.ppu_wbm_stb_i(stb),.ppu_wbm_wre_i(we),.ppu_wbm_ack_o(ack),
 .data_in(16'h7654),.drive(drive),.motor(motor),.step(step),.dir(dir),.head(head),
 .valid(1'b0),.sync(1'b0),.crc_ok(1'b0),.rdy(1'b1),.tr0(1'b1),.ind(1'b0),
 .wrprt_dsk(wp),.fdd_en(en));
mc0511_physical_fdd #(.SPINUP_CYCLES(100)) dut(
 .clk(clk),.reset(reset || !en),.selected(selected),.motor(motor),.step(step),
 .dir(dir),.head(head),.write_protect(wp[drive]),.bus_addr(adr),.bus_data(din),
 .bus_stb(stb),.bus_write(we),.bus_ack(ack),.bus_out(physical_dout),
 .index_in(idx),.track0_in(tr0),.protect_in(protect),.rdata_in(flux),
 .drive_out(ds),.motor_out(mot),.dir_out(di),.step_out(st),.side_out(side),
 .wgate_out(wg),.wdata_out(wd));
reg [15:0] result;
task bus(input bit writing,input bit datareg,input [15:0] value);
 integer n;
 begin
  @(negedge pclk);adr=datareg?17'o177132:17'o177130;din=value;stb=1;we=writing;
  n=0;
  // ACK is produced at the following rising PPU edge; the master samples
  // the returned data on the NEXT rising edge, as does the UKNC Wishbone bus.
  @(posedge pclk);#1;
  while(!ack && n<20)begin @(posedge pclk);#1;n=n+1;end
  if(!ack)$fatal(1,"No controller ACK");
  @(posedge pclk);result=dout;
  @(negedge pclk);stb=0;we=0;
  repeat(2)@(negedge pclk);
 end
endtask
function [15:0] command(input integer d,input [15:0] bits);
 command=16'h0400|((~d)&3)|bits;
endfunction
// Independent bit-at-a-time on-disk encoder and CRC reference.
reg previous=0;reg [15:0] disk_crc;
function [15:0] crc8(input [15:0] c,input [7:0] d);
 integer j;reg [15:0] v;
 begin v=c^{d,8'd0};for(j=0;j<8;j=j+1)v=v[15]?(v<<1)^16'h1021:v<<1;crc8=v;end
endfunction
task cell_bit(input bit b,input integer duration);
 begin flux=b;#200;flux=0;#(duration-200);end
endtask
task disk_byte(input [7:0] value,input bit marker,input integer duration);
 integer b;reg clock_bit;
 begin
  disk_crc=crc8(disk_crc,value);
  for(b=7;b>=0;b=b-1)begin
   clock_bit=!(previous|value[b]);
   if(marker && value==8'ha1 && b==2)clock_bit=0;
   cell_bit(clock_bit,duration);cell_bit(value[b],duration);previous=value[b];
  end
 end
endtask
reg [15:0] expect_word[0:259];
integer seen=0,expected_count=0;
reg reading=0,wait_marker=0;
always @(posedge dut.rx_valid)if(reading && (!wait_marker || dut.rx_data==16'ha1a1))begin
 wait_marker=0;
 bus(0,0,0);
 if(!result[7])$fatal(1,"Physical receive did not set TR, word %0d",seen);
 bus(0,1,0);
 if(result!==expect_word[seen])$fatal(1,"Read word %0d: %h expected %h",seen,result,expect_word[seen]);
 seen=seen+1;
 bus(0,0,0);if(result[7])$fatal(1,"Data read did not clear TR");
end
// Check the actual outgoing cable pulses against independently encoded words.
reg capture=0;integer written=0;time last_pulse=0,first_pulse=0;
reg [9215:0] captured=0;
always @(posedge wd)if(capture)begin
 if(last_pulse!=0 && (($time-last_pulse)%2000)!=0)$fatal(1,"MFM transition off channel grid");
 if(first_pulse==0)first_pulse=$time;
 captured[9215-(($time-first_pulse)/2000)]=1;
 last_pulse=$time;written=written+1;
end
reg [9215:0] expected_bits=0;integer expected_cells=0;reg tx_prev=0;
task expect_byte(input [7:0] value,input bit marker);
 integer b;reg c;
 begin
  for(b=7;b>=0;b=b-1)begin
   c=!(tx_prev|value[b]);if(marker && value==8'ha1 && b==2)c=0;
   expected_bits[9215-expected_cells]=c;expected_cells=expected_cells+1;
   expected_bits[9215-expected_cells]=value[b];expected_cells=expected_cells+1;
   tx_prev=value[b];
  end
 end
endtask
integer d,m,i,period;reg [15:0] crc_save;time step_start;
initial begin
 #2000;reset=0;#2000;
 if(ds!==0 || mot!==0 || wg!==0 || wd!==0 || st!==0)$fatal(1,"Not idle by default");
 for(m=0;m<=5;m=m+1)begin
  mapping=m;
  for(d=0;d<4;d=d+1)begin
   bus(1,0,command(d,16'h0010));#6000;
   if(m>=1 && m<=4 && d==m-1)begin
    if(ds!==1 || mot!==1)$fatal(1,"Physical mapping %0d / drive %0d",m,d);
    bus(0,0,0);if(result[2:0]!==3'b011)$fatal(1,"Physical status %h",result);
   end else begin
    if(ds!==0 || mot!==0 || wg!==0 || wd!==0 || st!==0)$fatal(1,"Unselected pins active");
    bus(0,1,0);if(result!==16'h7654)$fatal(1,"Image drive data changed");
   end
  end
 end
 mapping=1;bus(1,0,command(0,16'h0070));#6000;
 if(!di || !side)$fatal(1,"Direction/side polarity");
 fork
  begin bus(1,0,command(0,16'h00f0));end
  begin @(posedge st);step_start=$time;@(negedge st);if($time-step_start!=4000)$fatal(1,"STEP width %0t",$time-step_start);end
 join
 bus(1,0,command(0,16'h0210));
 if(!dut.mark)$fatal(1,"Side change discarded the same command's write-marker flag");
 // Good and corrupt sector CRC, with +/- 2% media speed.
 for(period=1960;period<=2040;period=period+40)begin
  bus(1,0,command(0,16'h0110));#2000;
  expect_word[0]=16'ha1a1;expect_word[1]=16'ha1fb;
  for(i=0;i<256;i=i+1)expect_word[i+2]={8'(i*2),8'(i*2+1)};
  seen=0;reading=1;previous=0;disk_crc=16'hffff;
  repeat(12)disk_byte(0,0,period);
  disk_crc=16'hffff;
  disk_byte(8'ha1,1,period);disk_byte(8'ha1,1,period);disk_byte(8'ha1,1,period);disk_byte(8'hfb,0,period);
  for(i=0;i<512;i=i+1)disk_byte(i[7:0],0,period);
  crc_save=disk_crc;if(period==2000)crc_save=crc_save^1;
  expect_word[258]=crc_save;
  disk_byte(crc_save[15:8],0,period);disk_byte(crc_save[7:0],0,period);
  #12000;reading=0;
  if(seen!=259)$fatal(1,"Wrong read word count %0d",seen);
  bus(0,0,0);if(result[14]!==(period!=2000))$fatal(1,"CRC result %h at period %0d",result,period);
  // The OS also reads successive fields without issuing GDR again. An
  // odd-sized gap tests byte/word realignment at the next marker as well.
  repeat(13)disk_byte(8'h4e,0,period);
  expect_word[0]=16'ha1a1;expect_word[1]=16'ha1fe;
  expect_word[2]=16'h0100;expect_word[3]=16'h0302;
  seen=0;reading=1;wait_marker=1;disk_crc=16'hffff;
  repeat(3)disk_byte(8'ha1,1,period);disk_byte(8'hfe,0,period);
  disk_byte(1,0,period);disk_byte(0,0,period);disk_byte(3,0,period);disk_byte(2,0,period);
  crc_save=disk_crc;expect_word[4]=crc_save;
  disk_byte(crc_save[15:8],0,period);disk_byte(crc_save[7:0],0,period);
  #12000;reading=0;
  if(seen!=5)$fatal(1,"Continuous field word count %0d",seen);
  bus(0,0,0);if(!result[14])$fatal(1,"CRC did not restart at the next field without GDR");
 end
 $display("PASS physical read: complete sectors, CRC rejection, +/-2%% speed, bus TR, continuous fields and odd-gap realignment");
 // Start with zeros so the first encoded cell is a clock pulse at grid origin.
 bus(1,0,command(0,16'h0010));capture=1;
 bus(1,1,16'h0000);expect_byte(0,0);expect_byte(0,0);
 // Queue a second word while the first shifts out.
 bus(1,1,16'h0000);expect_byte(0,0);expect_byte(0,0);
 wait(dut.tx_consumed);#1000;
 bus(1,0,command(0,16'h0210));
 bus(1,1,16'ha1a1);expect_byte(8'ha1,1);expect_byte(8'ha1,1);
 wait(dut.tx_consumed);#1000;
 bus(1,1,16'ha1fb);expect_byte(8'ha1,1);expect_byte(8'hfb,0);
 wait(dut.tx_consumed);#1000;
 bus(1,0,command(0,16'h0010));
 disk_crc=16'hffff;disk_crc=crc8(disk_crc,8'ha1);disk_crc=crc8(disk_crc,8'ha1);
 disk_crc=crc8(disk_crc,8'ha1);disk_crc=crc8(disk_crc,8'hfb);
 for(i=0;i<256;i=i+1)begin
  bus(1,1,{8'(i*2),8'(i*2+1)});expect_byte(8'(i*2),0);expect_byte(8'(i*2+1),0);
  disk_crc=crc8(disk_crc,8'(i*2));disk_crc=crc8(disk_crc,8'(i*2+1));
  wait(dut.tx_consumed);#1000;
 end
 expect_byte(disk_crc[15:8],0);expect_byte(disk_crc[7:0],0);
 wait(!wg);#1000;capture=0;
 if(captured!==expected_bits)$fatal(1,"Encoded flux / missing clock / CRC mismatch: got %h expected %h",captured,expected_bits);
 bus(0,0,0);if(!result[14])$fatal(1,"CRC completion status missing");
 $display("PASS physical write: exact MFM pulse stream, marker, buffering and automatic CRC");
 protect=1;#1000;bus(1,1,16'habcd);#1000;
 if(wg || wd)$fatal(1,"Hardware write protection bypassed");
 bus(0,0,0);if(!result[2])$fatal(1,"Hardware write protect not reported");
 protect=0;wp=1;#1000;bus(1,1,16'habcd);#1000;
 if(wg || wd)$fatal(1,"OSD write protection bypassed");
 wp=0;bus(1,1,16'habcd);#1000;if(!wg)$fatal(1,"Write did not start");
 protect=1;#200;if(wg || wd)$fatal(1,"Write protect did not abort active write");
 protect=0;#1000;if(wg)$fatal(1,"Stale write resumed after write protection");
 bus(1,1,16'habcd);#1000;
 mapping=0;#1;if(wg || wd || mot || ds || st)$fatal(1,"None did not abort physical access");
 #1000;mapping=1;#1000;if(wg)$fatal(1,"Stale write resumed after None");
 bus(1,1,16'habcd);#1000;en=0;#1;
 if(wg || wd || mot || ds || st)$fatal(1,"Controller Off did not abort physical access");
 en=1;#1000;bus(1,1,16'habcd);#1000;reset=1;#1;
 if(wg || wd || mot || ds || st)$fatal(1,"Reset did not abort physical access");
 $display("PASS all mappings, idle/reset/off, seek pulses, side/direction, image fallback, write protection and abort");
 $finish;
end
initial begin #100000000;$fatal(1,"Physical FDD test timeout");end
endmodule
