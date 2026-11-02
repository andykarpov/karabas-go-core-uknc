`timescale 1ns/1ps
module tb_floppy_latency;
reg clk=0;always #20 clk=~clk;
reg motor=0;reg [1:0] drive=0;
wire [3:0] request;wire [31:0] sector;wire [15:0] data_out;wire valid;
reg busy=0,done=0,byte_wr=0;reg [8:0] byte_addr=0;reg [7:0] byte_data=0;
fdd4 dut(.pin_25mhz_ck(clk),.ppu_vm_init_i(1'b0),.data_in(16'd0),.write(1'b0),
 .data_out(data_out),.drive(drive),.motor(motor),.step(1'b0),.dir(1'b0),.head(1'b0),
 .valid(valid),.rstart(request),.rsector(sector),.rbusy(busy),.rdone(done),
 .outen(byte_wr),.outaddr(byte_addr),.inbyte(byte_data),.mount_dsk(4'b1111),.sd_taken(1'b0));
function [7:0] pattern(input [31:0] lba,input integer b);pattern=(lba*13+b*3)^8'h5a;endfunction
integer requests=0,k,words=0;reg [31:0] served=0;reg loading=0;
always @(posedge clk)if(|request && !busy)begin
 if(request!=(1<<drive))$fatal(1,"Wrong drive request");
 busy<=1;loading=1;served=sector;requests=requests+1;
 // A long RP2040 main-loop / SD stall: original rotation would expose stale bytes.
 #30000000;
 for(k=0;k<512;k=k+1)begin
  @(negedge clk);byte_wr=1;byte_addr=k;byte_data=pattern(served,k);
 end
 @(negedge clk);byte_wr=0;done=1;busy=0;loading=0;
 @(negedge clk);done=0;
end
always @(posedge valid)if(dut._data)begin
 if(loading)$fatal(1,"Floppy exposed incomplete sector");
 if(data_out!=={pattern(served,2*dut.count_word),pattern(served,2*dut.count_word+1)})
  $fatal(1,"Bad sector word %d: %h",dut.count_word,data_out);
 words=words+1;
end
integer d;
initial begin
 #1000;
 for(d=0;d<4;d=d+1)begin
  @(negedge clk);drive=d;words=0;motor=1;
  wait(words==256);
  @(negedge clk);motor=0;
  #1000;
 end
 if(requests!=4)$fatal(1,"Missing drive reads");
 $display("PASS all four floppies: 30 ms host stall, 1024 exact words, no stale sector exposure");$finish;
end
initial begin #300000000;$fatal(1,"Floppy test timeout");end
endmodule
