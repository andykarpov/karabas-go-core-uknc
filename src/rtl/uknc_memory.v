// Synthesizable Xilinx memories replacing the Gowin IP boundaries.
module rom208(output reg [15:0] dout=0,input clk,ce,reset,oce,input [13:0] ad);
 reg [15:0] mem[0:16383];
 initial $readmemh("roms/uknc_rom.hex",mem);
 always @(posedge clk) if(ce) begin
  if(reset) dout<=0;else dout<=mem[ad];
 end
endmodule
module rawtr_prom(output reg [15:0] dout=0,input clk,ce,reset,oce,input [8:0] ad);
 reg [15:0] mem[0:511];
 initial $readmemh("roms/rawtrk.hex",mem);
 always @(posedge clk) if(ce) begin
  if(reset) dout<=0;else dout<=mem[ad];
 end
endmodule
module ide_rom(output reg [15:0] dout=0,input clk,ce,reset,input [13:0] ad);
 reg [15:0] mem[0:16383];
 initial $readmemh("roms/ide_wdrom.hex",mem);
 always @(posedge clk) if(ce) begin
  if(reset) dout<=0;else dout<=mem[ad];
 end
endmodule
// Byte port A and word port B share two independently writable byte lanes.
module dbufsec16(output wire [7:0] douta,output wire [15:0] doutb,
 input clka,ocea,cea,reseta,wrea,clkb,oceb,ceb,resetb,wreb,
 input [8:0] ada,input [7:0] dina,input [7:0] adb,input [15:0] dinb);
 reg [7:0] lo[0:255],hi[0:255];
 reg [7:0] alo=0,ahi=0,blo=0,bhi=0;
 reg lane=0;
 always @(posedge clka) if(cea) begin
  lane<=ada[0];
  if(wrea && !ada[0]) lo[ada[8:1]]<=dina;
  alo<=lo[ada[8:1]];
 end
 always @(posedge clka) if(cea) begin
  if(wrea && ada[0]) hi[ada[8:1]]<=dina;
  ahi<=hi[ada[8:1]];
 end
 always @(posedge clkb) if(ceb) begin
  if(wreb) lo[adb]<=dinb[7:0];
  blo<=lo[adb];
 end
 always @(posedge clkb) if(ceb) begin
  if(wreb) hi[adb]<=dinb[15:8];
  bhi<=hi[adb];
 end
 assign douta=lane?ahi:alo;
 assign doutb={bhi,blo};
endmodule
module uartfifo(input [7:0] Data,input WrClk,RdClk,WrEn,RdEn,
 output [7:0] Q,output Empty,Full);
 kg_async_fifo #(.DW(8),.AW(2)) fifo(.wclk(WrClk),.rclk(RdClk),
 .wreset(1'b0),.rreset(1'b0),.wr(WrEn),.rd(RdEn),.din(Data),.dout(Q),.empty(Empty),.full(Full),.rcount());
endmodule
