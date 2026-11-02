`timescale 1ns/1ps
// Pixel-level scoreboard driven through the MCU command interface. No RAM
// forcing: check cell boundaries, asymmetric glyphs, attributes and all rows.
module tb_osd;
reg clk=0; always #10 clk=~clk;
reg hs=0,vs=0;
reg [15:0] command=0;
wire [23:0] rgb;
localparam [23:0] VIDEO=24'hb8a890, DIM=24'h171512;
kg_osd_overlay #(.H_OFFSET(4),.V_OFFSET(2)) dut(
 .clk(clk),.rgb_i(VIDEO),.rgb_o(rgb),.hsync_i(hs),.vsync_i(vs),.osd_command(command));
integer checks=0, errors=0;
function [7:0] glyph(input integer ch,input integer row);
 begin
  case(ch%8)
   0:glyph=8'hff;
   1:glyph=8'haa;
   2:glyph=8'h81;
   3:glyph=8'h01;
   4:glyph=8'h80;
   5:glyph=8'h00;
   6:glyph=8'h80 >> row;
   7:glyph=8'h13 ^ (row*19);
  endcase
 end
endfunction
task send(input [15:0] value);
 begin @(negedge clk); command=value; repeat(5) @(negedge clk); end
endtask
task frame(input integer scale,input integer popup,input integer enabled,input integer verify);
 integer x,y,h,v,c,r,b,span;
 reg [7:0] bits;
 reg [23:0] expected,ink,paper;
 begin
  span=popup?16:8;
  for(y=0;y<625;y=y+1)begin
   for(x=0;x<400*scale;x=x+1)begin
    @(negedge clk); hs=x<8;vs=y==0;
    @(posedge clk); #1;
    if(verify)begin
     // 625 physical lines are scaled two-to-one; x advances every scale
     // clocks. Read-ahead places column zero one whole cell after offset.
     h=x/scale-4; v=y/2-2;
     expected=enabled?DIM:VIDEO;
     if(enabled && h>=span && h<256+span && v>=0 && v<208)begin
      c=h/span-1;r=v/span;
      bits=glyph((c+r)%8,(v/(popup?2:1))%8);
      b=(h/(popup?2:1))%8;
      ink=(c%2)?24'h00e000:24'he0e0e0;
      paper=(c%2)?24'h0000e0:24'he00000;
      expected=bits[7-b]?ink:paper;
     end
     checks=checks+1;
     if(rgb!==expected)begin
      if(errors<12)$display("FAIL scale=%0d popup=%0d enabled=%0d x=%0d y=%0d rgb=%h expected=%h",scale,popup,enabled,x,y,rgb,expected);
      errors=errors+1;
     end
    end
   end
  end
 end
endtask
integer c,r,s,p;
initial begin
 send(16'h2001);
 for(c=0;c<8;c=c+1)for(r=0;r<8;r=r+1)begin
  send(16'h2100 | glyph(c,r));send(0);
 end
 for(r=0;r<26;r=r+1)begin
  send(16'h1100 | r);
  for(c=0;c<32;c=c+1)begin
   send(16'h1000 | c);send(16'h1200 | ((c+r)%8));
   send(c%2 ? 16'h1353 : 16'h13f9);
  end
 end
 for(s=1;s<=4;s=s*2)for(p=0;p<=1;p=p+1)begin
  send(16'h0101);send(16'h0200 | p);
  frame(s,p,1,0); // acquire line and frame dimensions
  frame(s,p,1,1);
  $display("Checked scale=%0d popup=%0d",s,p);
 end
 send(16'h0100);send(16'h0200);
 frame(4,0,0,1);
 if(errors)$fatal(1,"FAIL OSD: %0d errors in %0d pixel checks",errors,checks);
 $display("PASS OSD: %0d pixel checks, all scales, normal/popup, colors, edges, disabled",checks);
 $finish;
end
endmodule
