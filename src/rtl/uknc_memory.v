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
// RAMB8BWER by hand: inferred from two always blocks, in the whole design XST 14.7 made RAM128X1D
// (one write port) out of this, also with ram_style = "block", and dropped the writes of port B
// without a warning (the floppy sent the old sectors to the card). As a module alone it inferred fine.
module dbufsec16(output wire [7:0] douta,output wire [15:0] doutb,
 input clka,ocea,cea,reseta,wrea,clkb,oceb,ceb,resetb,wreb,
 input [8:0] ada,input [7:0] dina,input [7:0] adb,input [15:0] dinb);
 reg lane=0;
 always @(posedge clka) if(cea) lane<=ada[0];
 wire [7:0] alo,ahi;
 assign douta=lane?ahi:alo;
 dbufsec16_lane lane_lo(.clka(clka),.cea(cea),.wea(wrea && !ada[0]),.ada(ada[8:1]),.dia(dina),.doa(alo),
  .clkb(clkb),.ceb(ceb),.web(wreb),.adb(adb),.dib(dinb[7:0]),.dob(doutb[7:0]));
 dbufsec16_lane lane_hi(.clka(clka),.cea(cea),.wea(wrea && ada[0]),.ada(ada[8:1]),.dia(dina),.doa(ahi),
  .clkb(clkb),.ceb(ceb),.web(wreb),.adb(adb),.dib(dinb[15:8]),.dob(doutb[15:8]));
endmodule
module dbufsec16_lane(input clka,cea,wea,input [7:0] ada,dia,output [7:0] doa,
 input clkb,ceb,web,input [7:0] adb,dib,output [7:0] dob);
 wire [15:0] qa,qb;
 assign doa=qa[7:0];
 assign dob=qb[7:0];
 RAMB8BWER #(.RAM_MODE("TDP"),.DATA_WIDTH_A(9),.DATA_WIDTH_B(9),.DOA_REG(0),.DOB_REG(0),
  .WRITE_MODE_A("READ_FIRST"),.WRITE_MODE_B("READ_FIRST")) ram(
  .CLKAWRCLK(clka),.ENAWREN(cea),.REGCEA(1'b0),.RSTA(1'b0),.WEAWEL({2{wea}}),
  .ADDRAWRADDR({2'b00,ada,3'b000}),.DIADI({8'd0,dia}),.DIPADIP(2'b00),.DOADO(qa),.DOPADOP(),
  .CLKBRDCLK(clkb),.ENBRDEN(ceb),.REGCEBREGCE(1'b0),.RSTBRST(1'b0),.WEBWEU({2{web}}),
  .ADDRBRDADDR({2'b00,adb,3'b000}),.DIBDI({8'd0,dib}),.DIPBDIP(2'b00),.DOBDO(qb),.DOPBDOP());
endmodule
module uartfifo(input [7:0] Data,input WrClk,RdClk,WrEn,RdEn,
 output [7:0] Q,output Empty,Full);
 kg_async_fifo #(.DW(8),.AW(2)) fifo(.wclk(WrClk),.rclk(RdClk),
 .wreset(1'b0),.rreset(1'b0),.wr(WrEn),.rd(RdEn),.din(Data),.dout(Q),.empty(Empty),.full(Full),.rcount());
endmodule
