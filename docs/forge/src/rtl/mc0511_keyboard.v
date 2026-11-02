// USB boot reports to the UKNC row protocol. Source: mnano/uknc.h.
// Wait for the seven-frame report to settle; emit row release before rollover press.
module mc0511_keyboard #(parameter EVENT_CYCLES=25000)(
 input wire clk,reset,input wire [55:0] report,output reg [7:0] keycode=0);
function [7:0] translate;
 input [7:0] usb;
 begin case(usb)
8'h04:translate=8'o72;
8'h05:translate=8'o76;
8'h06:translate=8'o50;
8'h07:translate=8'o57;
8'h08:translate=8'o33;
8'h09:translate=8'o47;
8'h0a:translate=8'o55;
8'h0b:translate=8'o156;
8'h0c:translate=8'o73;
8'h0d:translate=8'o27;
8'h0e:translate=8'o52;
8'h0f:translate=8'o56;
8'h10:translate=8'o112;
8'h11:translate=8'o54;
8'h12:translate=8'o75;
8'h13:translate=8'o53;
8'h14:translate=8'o67;
8'h15:translate=8'o74;
8'h16:translate=8'o111;
8'h17:translate=8'o114;
8'h18:translate=8'o51;
8'h19:translate=8'o137;
8'h1a:translate=8'o71;
8'h1b:translate=8'o115;
8'h1c:translate=8'o70;
8'h1d:translate=8'o157;
8'h1e:translate=8'o30;
8'h1f:translate=8'o31;
8'h20:translate=8'o32;
8'h21:translate=8'o13;
8'h22:translate=8'o34;
8'h23:translate=8'o35;
8'h24:translate=8'o16;
8'h25:translate=8'o17;
8'h26:translate=8'o177;
8'h27:translate=8'o176;
8'h28:translate=8'o153;
8'h29:translate=8'o6;
8'h2a:translate=8'o132;
8'h2b:translate=8'o26;
8'h2c:translate=8'o113;
8'h2d:translate=8'o175;
8'h2e:translate=8'o175;
8'h2f:translate=8'o36;
8'h30:translate=8'o37;
8'h31:translate=8'o136;
8'h32:translate=8'o77;
8'h33:translate=8'o7;
8'h34:translate=8'o155;
8'h35:translate=8'o77;
8'h36:translate=8'o117;
8'h37:translate=8'o135;
8'h38:translate=8'o173;
8'h39:translate=8'o107;
8'h3a:translate=8'o10;
8'h3b:translate=8'o11;
8'h3c:translate=8'o12;
8'h3d:translate=8'o14;
8'h3e:translate=8'o15;
8'h3f:translate=8'o172;
8'h40:translate=8'o152;
8'h41:translate=8'o151;
8'h42:translate=8'o171;
8'h43:translate=8'o4;
8'h4f:translate=8'o133;
8'h50:translate=8'o116;
8'h51:translate=8'o134;
8'h52:translate=8'o154;
8'h54:translate=8'o173;
8'h55:translate=8'o174;
8'h56:translate=8'o25;
8'h57:translate=8'o131;
8'h58:translate=8'o166;
8'h59:translate=8'o127;
8'h5a:translate=8'o147;
8'h5b:translate=8'o167;
8'h5c:translate=8'o130;
8'h5d:translate=8'o150;
8'h5e:translate=8'o170;
8'h5f:translate=8'o125;
8'h60:translate=8'o145;
8'h61:translate=8'o165;
8'h62:translate=8'o126;
8'h63:translate=8'o146;
default:translate=0;
endcase end endfunction
reg [7:0] wanted[0:15];
reg [7:0] held[0:15];
reg [55:0] previous_report=0;
reg [15:0] quiet=0;
reg [3:0] row=0;
reg [31:0] spacing=0;
reg [7:0] code;
integer i,j;
initial for(i=0;i<16;i=i+1) held[i]=0;
always @* begin
 for(j=0;j<16;j=j+1) wanted[j]=0;
 for(j=1;j<=6;j=j+1) begin
  code=translate(report[j*8 +: 8]);
  if(code!=0) wanted[code[3:0]]=code;
 end
 if(report[0]) wanted[6]=8'o46;
 if(report[1]) wanted[5]=8'o105;
 if(report[2]) wanted[6]=8'o106;
 if(report[4]) wanted[6]=8'o46;
 if(report[5]) wanted[5]=8'o105;
 if(report[6]) wanted[6]=8'o66;
end
always @(posedge clk) begin
 previous_report<=report;
 if(report!=previous_report) quiet<=0;
 else if(quiet!=16'hffff) quiet<=quiet+1'b1;
 if(spacing!=0) spacing<=spacing-1'b1;
 if(reset) begin
  for(i=0;i<16;i=i+1) held[i]<=0;
  keycode<=0;row<=0;spacing<=EVENT_CYCLES;
 end else if(spacing==0 && quiet>=EVENT_CYCLES) begin
  if(held[row]!=wanted[row]) begin
   if(held[row]!=0) begin keycode<={4'h8,row};held[row]<=0;end
   else begin keycode<=wanted[row];held[row]<=wanted[row];end
   spacing<=EVENT_CYCLES;
  end else row<=row+1'b1;
 end
end
endmodule
