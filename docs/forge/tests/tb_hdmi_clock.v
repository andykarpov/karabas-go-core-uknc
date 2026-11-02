`timescale 1ns/1ps
module tb_hdmi_clock;
reg clk=0,reset=1;always #10 clk=~clk;
wire [3:0] p,n;
mc0511_hdmi dut(.clk(clk),.reset(reset),.rgb(24'h123456),.hs(1'b0),.vs(1'b0),.de(1'b0),
 .audio_l(16'h8001),.audio_r(16'h7ffe),.tmds_p(p),.tmds_n(n));
integer count=0; real previous=0;
always @(negedge dut.locked) previous=0;
always @(posedge dut.serial) if(dut.locked && !dut.reset_sync[2]) begin
 if(previous && ($realtime-previous<3.99 || $realtime-previous>4.01)) $fatal(1,"Not 250 MHz");
 previous=$realtime;count=count+1;
end
initial begin
 #1000;reset=0;wait(!dut.reset_sync[2]);#100000;
 if(count<24000 || p!==(~n)) $fatal(1,"Clock/serializer did not start");
 reset=1;#500;reset=0;wait(!dut.reset_sync[2]);#10000;
 $display("PASS HDMI vendor DCM: 50 MHz -> 250 MHz, complementary outputs, reset/relock");$finish;
end
initial begin #500000;$fatal(1,"HDMI clock timeout");end
endmodule
