// KG1 / Karabas GO B4 board wrapper.
module karabas_go_top (
   //---------------------------
   input wire CLK_50MHZ,

	//---------------------------
	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,
	inout wire ESP_RESET_N,
	inout wire ESP_BOOT_N,
	
   //---------------------------
   output wire [20:0] MA,
   inout wire [15:0] MD,
   output wire [1:0] MWR_N,
   output wire [1:0] MRD_N,

   //---------------------------
	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

   //---------------------------
   output wire SD_CS_N,
   output wire SD_CLK,
   inout wire SD_DI,
   inout wire SD_DO,
	input wire SD_DET_N,

   //---------------------------
   output wire [7:0] VGA_R,
   output wire [7:0] VGA_G,
   output wire [7:0] VGA_B,
   output wire VGA_HS,
   output wire VGA_VS,
	output wire V_CLK,
	
	//---------------------------
	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	output wire FT_OE_N,

	//---------------------------
	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,
	
	//---------------------------
	input wire FDC_INDEX,
	output wire [1:0] FDC_DRIVE,
	output wire FDC_MOTOR,
	output wire FDC_DIR,
	output wire FDC_STEP,
	output wire FDC_WDATA,
	output wire FDC_WGATE,
	input wire FDC_TR00,
	input wire FDC_WPRT,
	input wire FDC_RDATA,
	output wire FDC_SIDE_N,

   //---------------------------	
	output wire TAPE_OUT,
	input wire TAPE_IN,
	output wire BEEPER,
	
	//---------------------------
	output wire DAC_LRCK,
   output wire DAC_DAT,
   output wire DAC_BCK,
   output wire DAC_MUTE,
	
	//---------------------------
	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	input wire MCU_SPI_FT_CS_N,
	input wire MCU_SPI_SD2_CS_N,	
	inout wire [1:0] MCU_SPI_IO,
	
	//---------------------------
	output wire MIDI_TX,
	output wire MIDI_CLK,
	output wire MIDI_RESET_N,
	
	//---------------------------
	output wire FLASH_CS_N,
	input wire  FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N	
   );

wire [5:0] clocks;
wire locked;
// 400 MHz VCO supplies every machine clock on a PLL/BUFG path.
// Host phase 180 aligns its falling edge with the PPU rising edge.
kg_pll #(.CLKFBOUT_MULT(8),.CLKOUT0_DIVIDE(8),.CLKOUT1_DIVIDE(96),
 .CLKOUT2_DIVIDE(8),.CLKOUT2_PHASE(56.25),
 .CLKOUT3_DIVIDE(16),.CLKOUT3_PHASE(180.0),.CLKOUT4_DIVIDE(128),
 .BUFG_MASK(6'b011111)) pll(
 .clk_in(CLK_50MHZ),.rst(1'b0),.clk_out(clocks),.locked(locked));
wire [10:0] ram_addr;
wire [23:0] rgb;
wire hs,vs,de;
wire [15:0] audio_l,audio_r;
wire ram_cs, audio_clock;
// Tang's serializer updates DIN/LRCK on the PPU rising edge. The PCM5102
// samples BCK rising: invert its forwarded clock for half-cycle setup/hold.
ODDR2 dac_clock(.Q(DAC_BCK),.C0(audio_clock),.C1(~audio_clock),.CE(1'b1),.D0(1'b0),.D1(1'b1),.R(1'b0),.S(1'b0));
assign SDR_A={2'b00,ram_addr};
ODDR2 ram_clock(.Q(SDR_CLK),.C0(clocks[2]),.C1(~clocks[2]),.CE(1'b1),.D0(1'b1),.D1(1'b0),.R(1'b0),.S(1'b0));
ODDR2 video_clock(.Q(V_CLK),.C0(clocks[0]),.C1(~clocks[0]),.CE(1'b1),.D0(1'b1),.D1(1'b0),.R(1'b0),.S(1'b0));
mc0511_machine machine(
 .clkram(clocks[0]),.clk4(clocks[1]),.clk_25(clocks[3]),.clk_3_12(clocks[4]),.locked(locked),
 .O_sdram_addr(ram_addr),.IO_sdram_dq(SDR_DQ),.O_sdram_ba(SDR_BA),.O_sdram_dqm(SDR_DQM),
 .O_sdram_cs_n(ram_cs),.O_sdram_wen_n(SDR_WE_N),.O_sdram_ras_n(SDR_RAS_N),.O_sdram_cas_n(SDR_CAS_N),
 .MCU_SCK(MCU_SCK),.MCU_CS_N(MCU_CS_N),.MCU_MOSI(MCU_MOSI),.MCU_MISO(MCU_MISO),
 // GO reverses the FPGA indices relative to the RP2040 IO names:
 // RP2040 IO0 / GPIO14 is M11 (FPGA IO[1]); READY is N9 (FPGA IO[0]).
 .MCU_BURST_CS_N(MCU_SPI_IO[1]),.MCU_BURST_READY(MCU_SPI_IO[0]),
 .rgb(rgb),.hsync(hs),.vsync(vs),.visible(de),.beeper(BEEPER),.audio_l(audio_l),.audio_r(audio_r),
 .HP_BCK(audio_clock),.HP_WS(DAC_LRCK),.HP_DIN(DAC_DAT),.uart_rx(UART_RX),.uart_tx(UART_TX),
 .FDC_INDEX(FDC_INDEX),.FDC_TR00(FDC_TR00),.FDC_WPRT(FDC_WPRT),.FDC_RDATA(FDC_RDATA),
 .FDC_DRIVE(FDC_DRIVE),.FDC_MOTOR(FDC_MOTOR),.FDC_DIR(FDC_DIR),.FDC_STEP(FDC_STEP),
 .FDC_WDATA(FDC_WDATA),.FDC_WGATE(FDC_WGATE),.FDC_SIDE_N(FDC_SIDE_N));
assign {VGA_R,VGA_G,VGA_B}=rgb;
assign VGA_HS=~hs;
assign VGA_VS=~vs;
assign DAC_MUTE=1'b1;
assign MA=21'd0;
assign MD=16'hzzzz;
assign MWR_N=2'b11;
assign MRD_N=2'b11;
assign SD_CS_N=1'b1;
assign SD_CLK=1'b0;
assign SD_DI=1'bz;
assign SD_DO=1'bz;
assign FT_SPI_CS_N=1'b1;
assign FT_SPI_SCK=1'b0;
assign FT_SPI_MOSI=1'b0;
assign FT_OE_N=1'b1;
assign WA=3'd0;
assign WCS_N=2'b11;
assign WRD_N=1'b1;
assign WWR_N=1'b1;
assign WRESET_N=1'b0;
assign WD=16'hzzzz;
assign TAPE_OUT=1'b0;
assign UART_CTS=1'bz;
assign ESP_RESET_N=1'bz;
assign ESP_BOOT_N=1'bz;
assign MIDI_TX=1'b1;
assign MIDI_CLK=1'b0;
assign MIDI_RESET_N=1'b0;
assign FLASH_CS_N=1'b1;
assign FLASH_DI=1'b1;
assign FLASH_SCK=1'b0;
assign FLASH_WP_N=1'b1;
assign FLASH_HOLD_N=1'b1;
endmodule
