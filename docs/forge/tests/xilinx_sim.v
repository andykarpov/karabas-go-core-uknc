`timescale 1ns/1ps
// Clock-only simulation models. Never include this file in an ISE project.
module BUFG(input I,output O); assign O=I; endmodule
module ODDR2 #(parameter DDR_ALIGNMENT="NONE", parameter INIT=0,
 parameter SRTYPE="SYNC") (output reg Q=INIT,input C0,C1,CE,D0,D1,R,S);
 always @(posedge C0) if(R) Q<=0; else if(S) Q<=1; else if(CE) Q<=D0;
 always @(posedge C1) if(R) Q<=0; else if(S) Q<=1; else if(CE) Q<=D1;
endmodule
module PLL_BASE #(
 parameter BANDWIDTH="OPTIMIZED", parameter CLK_FEEDBACK="CLKFBOUT", parameter COMPENSATION="SYSTEM_SYNCHRONOUS",
 parameter DIVCLK_DIVIDE=1, parameter CLKFBOUT_MULT=1, parameter CLKFBOUT_PHASE=0.0,
 parameter CLKIN_PERIOD=20.0, parameter REF_JITTER=0.01, parameter RESET_ON_LOSS_OF_LOCK="FALSE",
 parameter CLKOUT0_DIVIDE=1,CLKOUT1_DIVIDE=1,CLKOUT2_DIVIDE=1,CLKOUT3_DIVIDE=1,CLKOUT4_DIVIDE=1,CLKOUT5_DIVIDE=1,
 parameter CLKOUT0_DUTY_CYCLE=0.5,CLKOUT1_DUTY_CYCLE=0.5,CLKOUT2_DUTY_CYCLE=0.5,CLKOUT3_DUTY_CYCLE=0.5,CLKOUT4_DUTY_CYCLE=0.5,CLKOUT5_DUTY_CYCLE=0.5,
 parameter CLKOUT0_PHASE=0.0,CLKOUT1_PHASE=0.0,CLKOUT2_PHASE=0.0,CLKOUT3_PHASE=0.0,CLKOUT4_PHASE=0.0,CLKOUT5_PHASE=0.0
)(input CLKIN, CLKFBIN,RST, output CLKFBOUT,
output reg CLKOUT0=0,CLKOUT1=0,CLKOUT2=0,CLKOUT3=0,CLKOUT4=0,CLKOUT5=0,output reg LOCKED=0);
localparam real T=CLKIN_PERIOD*DIVCLK_DIVIDE/CLKFBOUT_MULT/2.0;
initial begin @(posedge CLKIN); #(2*T*CLKOUT0_DIVIDE*CLKOUT0_PHASE/360.0); CLKOUT0=1; forever #(T*CLKOUT0_DIVIDE) CLKOUT0=~CLKOUT0; end
initial begin @(posedge CLKIN); #(2*T*CLKOUT1_DIVIDE*CLKOUT1_PHASE/360.0); CLKOUT1=1; forever #(T*CLKOUT1_DIVIDE) CLKOUT1=~CLKOUT1; end
initial begin @(posedge CLKIN); #(2*T*CLKOUT2_DIVIDE*CLKOUT2_PHASE/360.0); CLKOUT2=1; forever #(T*CLKOUT2_DIVIDE) CLKOUT2=~CLKOUT2; end
initial begin @(posedge CLKIN); #(2*T*CLKOUT3_DIVIDE*CLKOUT3_PHASE/360.0); CLKOUT3=1; forever #(T*CLKOUT3_DIVIDE) CLKOUT3=~CLKOUT3; end
initial begin @(posedge CLKIN); #(2*T*CLKOUT4_DIVIDE*CLKOUT4_PHASE/360.0); CLKOUT4=1; forever #(T*CLKOUT4_DIVIDE) CLKOUT4=~CLKOUT4; end
assign CLKFBOUT=CLKIN;
initial begin #1000; LOCKED=1; end
endmodule
module IBUFG(input I,output O);assign O=I;endmodule
