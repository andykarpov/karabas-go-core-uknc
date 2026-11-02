`timescale 1ns/1ps
module tb_keyboard_adapter;
reg clk=0;always #20 clk=~clk;
reg reset=1;reg [55:0] report=0;wire [7:0] keycode;
mc0511_keyboard #(.EVENT_CYCLES(8)) dut(clk,reset,report,keycode);
integer count=0;reg [7:0] seen[0:31];reg [7:0] last=0;
always @(posedge clk)if(keycode!=last)begin seen[count]=keycode;count=count+1;last=keycode;end
initial begin
 #200;reset=0;
 report[7:0]=2;report[15:8]=8'h34; // Shift + apostrophe, separate rows
 #10000;
 if(count!=2 || seen[0]!=8'o105 || seen[1]!=8'o155)$fatal(1,"Shift+apostrophe");
 report=0;#10000;
 if(count!=4 || seen[2]!=8'h85 || seen[3]!=8'h8d)$fatal(1,"Release rows");
 report[15:8]=8'h04;#10000; // A row 10
 report[23:16]=8'h2a;#10000; // Backspace in same row: release + press
 if(count!=7 || seen[4]!=8'o72 || seen[5]!=8'h8a || seen[6]!=8'o132)$fatal(1,"Same-row rollover");
 report=0;#10000;
 if(keycode!=8'h8a)$fatal(1,"Release backspace");
 $display("PASS USB UKNC keyboard chords, releases and rollover");$finish;
end
endmodule
