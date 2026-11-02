`timescale 1ns/1ps
module tb_audio_pins;
reg audio_clock=0;always #160 audio_clock=~audio_clock;
reg reset_n=0;
wire DAC_BCK,DAC_DAT,DAC_LRCK;
reg [15:0] left=16'ha596,right=16'h5a69;
audio_drive serializer(.clk_1p536m(audio_clock),.rst_n(reset_n),.idata(left),.idata_rgt(right),
 .HP_WS(DAC_LRCK),.HP_DIN(DAC_DAT));
// Extracted verbatim from the board wrapper by test_audio.py.
`include "board_dac_clock.vh"
realtime changed=0;
always @(DAC_DAT or DAC_LRCK)begin
 if(reset_n && $realtime>1000 && DAC_BCK!==0)$fatal(1,"DAC data changes on sampling half-cycle");
 changed=$realtime;
end
reg previous_ws=0,armed=0,channel=0;
reg [15:0] received=0;
integer bits=0,words=0;
always @(posedge DAC_BCK)if(reset_n)begin
 if($realtime>1000 && $realtime-changed<150)$fatal(1,"Insufficient DAC setup time");
 if(armed)begin
  received={received[14:0],DAC_DAT};bits=bits+1;
  if(bits==16)begin
   if(received!==(channel?right:left))$fatal(1,"I2S channel%0d got%h expected%h",channel,received,channel?right:left);
   words=words+1;bits=0;
  end
 end
 if(DAC_LRCK!=previous_ws)begin
  if(armed && bits!=0)$fatal(1,"Wrong I2S word length");
  armed=1;channel=DAC_LRCK;
 end
 previous_ws=DAC_LRCK;
end
initial begin
 #1000;reset_n=1;
 #1000000;
 if(words<100)$fatal(1,"No audio words decoded");
 $display("PASS: %0d exact stereo I2S words, data/LRCK change at BCK falling with 160 ns setup",words);$finish;
end
endmodule
