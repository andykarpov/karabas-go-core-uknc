`timescale 1ns/1ps
// Actual UKNC raster, Mini HDMI sampler and unmodified HDMI signaling/packet/audio logic.
// Core-mode pixel clock only; PLL/serializer electrical behavior is not modeled.
module tb_hdmi_audio_packets;
localparam RATE=48000,N=6144;
reg clk=0;always #10 clk=~clk;
reg reset=1;
wire hs,vs,visible;
sdram2 raster(.clkram(clk),.lockclk(!reset),.hsync(hs),.vsync(vs),.visible(visible),
 .cpu_addr(19'd0),.cpu_din(32'd0),.cpu_dqm(4'd0),.cpu_read(1'b0),.cpu_wrte(1'b0),
 .ppu_addr(19'd0),.ppu_din(32'd0),.ppu_dqm(4'd0),.ppu_read(1'b0),.ppu_wrte(1'b0));
reg [15:0] ramp=0;
always @(negedge clk) ramp<=ramp+16'h1357;
mc0511_hdmi hdmi(.clk(clk),.reset(reset),.rgb({ramp,8'h5a}),.hs(~hs),.vs(~vs),.de(visible),
 .audio_l(ramp),.audio_r(~ramp),.tmds_p(),.tmds_n());
wire audio_clk=hdmi.sample;
wire [23:0] left=hdmi.left,right=hdmi.right;
wire de=hdmi.tx.signaler.de,ae=hdmi.tx.signaler.ae,dgb=hdmi.tx.signaler.dgb;
reg [47:0] expected[0:16383];reg [7:0] packet[0:30];
integer pushed=0,popped=0,idx=0,packets=0,acrs=0,maxqueue=0,j,pos,cts,nfield;
reg [23:0] got_l,got_r;
// The transmitter learns sync polarity/blanking from the first lines.
// Check island clipping after acquisition; packet contents/rate are checked from reset.
integer lines=0;
always @(posedge hs) lines=lines+1;
reg previous_packet=0;
always @(posedge clk) begin
 if(hdmi.reset_sync[2]) previous_packet<=0;
 else begin
  if(lines>2 && previous_packet && (!ae || de || dgb)) $fatal(1,"Data island clipped by active video");
  previous_packet<=hdmi.tx.signaler.enc_packet;
 end
end
always @(posedge clk) begin
 if(hdmi.reset_sync[2]) begin pushed=0;popped=0;idx=0;packets=0;acrs=0;maxqueue=0;end
 else begin
  if(audio_clk) begin
   if(pushed>=16384) $fatal(1,"test queue capacity");
   expected[pushed]={left,right};pushed=pushed+1;
   if((hdmi.tx.signaler.pkgen.audio_packetizer.buf_end+3'd1)==hdmi.tx.signaler.pkgen.audio_packetizer.buf_beg)
    $fatal(1,"HDMI audio buffer overflow");
  end
  if(pushed-popped>maxqueue) maxqueue=pushed-popped;
  if(hdmi.tx.signaler.packet_ready && hdmi.tx.signaler.packet_valid) begin
   packet[idx]=hdmi.tx.signaler.packet_data;
   if(idx==30) begin
    if(packet[0]==2) begin
     packets=packets+1;
     for(j=0;j<4;j=j+1) if(packet[1][j]) begin
      pos=3+j*7;
      got_l={packet[pos+2],packet[pos+1],packet[pos]};
      got_r={packet[pos+5],packet[pos+4],packet[pos+3]};
      if(popped>=pushed || {got_l,got_r}!==expected[popped])
       $fatal(1,"Audio packet reordered/dropped/corrupt at sample %0d: got=%h/%h expected=%h",popped,got_l,got_r,expected[popped]);
      if((^got_l)^(^packet[pos+6][3:0]) || (^got_r)^(^packet[pos+6][7:4]))
       $fatal(1,"Audio parity error");
      popped=popped+1;
     end
    end else if(packet[0]==1) begin
     cts={packet[4][3:0],packet[5],packet[6]};nfield={packet[7][3:0],packet[8],packet[9]};
     if(nfield!=N) $fatal(1,"Wrong ACR N=%0d expected=%0d",nfield,N);
     // The first measurement starts with reset release, not a sample edge.
     if(acrs>0 && (cts<49999 || cts>50001)) $fatal(1,"Wrong ACR CTS=%0d expected=%0d",cts,50000);
     acrs=acrs+1;
    end
    idx=0;
   end else idx=idx+1;
  end
 end
end
integer last_sample=0,cycles=0,samples=0;
always @(posedge clk) if(!hdmi.reset_sync[2]) begin
 cycles=cycles+1;
 if(audio_clk) begin
  if(last_sample && cycles-last_sample!=1041 && cycles-last_sample!=1042)
   $fatal(1,"Incorrect 48 kHz sample spacing");
  if(left!=={ramp-16'h1357,8'd0} || right!=={~(ramp-16'h1357),8'd0})
   $fatal(1,"Signed stereo capture corrupted");
  last_sample=cycles;samples=samples+1;
 end
end
initial begin
 repeat(20) @(negedge clk);reset=0;
 repeat(4) @(posedge vs);
 @(negedge clk);
 if(popped<2000 || pushed-popped>7 || acrs<3) $fatal(1,"Insufficient/draining audio packets");
 if(samples*50000000.0/cycles<47980 || samples*50000000.0/cycles>48020) $fatal(1,"Sample rate drift");
 $display("PASS HDMI packets: UKNC raster, 48 kHz fractional PCM, accepted=%0d delivered=%0d packets=%0d ACR=%0d max_pending=%0d",pushed,popped,packets,acrs,maxqueue);
 $finish;
end
initial begin #100000000;$fatal(1,"Timeout");end
endmodule
