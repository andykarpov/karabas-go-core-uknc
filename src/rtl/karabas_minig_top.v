`timescale 1ns / 1ps
`default_nettype none
/*-------------------------------------------------------------------------------------------------------------------
--
--
-- #       #######                                                 #
-- #                                                               #
-- #                                                               #
-- ############### ############### ############### ############### ############### ############### ###############
-- #             #               # #                             # #             #               # #
-- #             # ############### #               ############### #             # ############### ###############
-- #             # #             # #               #             # #             # #             #               #
-- #             # ############### #               ############### ############### ############### ###############
--
--         ####### ####### ####### #######                                         ############### ###############
--                                                                                 #               #             #
--                                                                                 #   ########### #             #
--                                                                                 #             # #             #
-- https://github.com/andykarpov/karabas-go                                        ############### ###############
--
-- UKNC (Elektronika MS-0511) core for Karabas-Go Mini G
--
-- The machine is tang-uknc (c) Alexey Gurov, Sergei Lemeshev and contributors (MIT).
-- The port to Karabas: Sergei Lemeshev (lordamot), 2026 (karabas-forge mc0511).
-- The board wrapper after the TS-Conf / BaseConf cores: Andy Karpov <andy.karpov@gmail.com>
------------------------------------------------------------------------------------------------------------------*/

module karabas_minig_top (
	//------------------ global clock --------
	input wire 				CLK_50MHZ,

	//------------------ esp8266 uart --------
	inout wire 				UART_RX,
	inout wire 				UART_TX,
	inout wire 				UART_CTS,

	//------------------ sram ----------------
	output wire [20:0] 	MA,
	inout wire [15:0] 	MD,
	output wire [1:0] 	MWR_N,
	output wire [1:0] 	MRD_N,

	//------------------ sdram ---------------
	output wire [1:0] 	SDR_BA,
	output wire [12:0] 	SDR_A,
	output wire 			SDR_CLK,
	output wire [1:0] 	SDR_DQM,
	output wire 			SDR_WE_N,
	output wire 			SDR_CAS_N,
	output wire 			SDR_RAS_N,
	inout wire [15:0] 	SDR_DQ,

	//------------------ sd2 -----------------
	output wire 			SD_CS_N,
	output wire 			SD_CLK,
	inout wire 				SD_DI,
	inout wire 				SD_DO,
	input wire 				SD_DET_N,

	//------------------ ft812 rgb + sync ----
	input wire [7:0] 		VGA_R,
	input wire [7:0] 		VGA_G,
	input wire [7:0] 		VGA_B,
	input wire 				VGA_HS,
	input wire 				VGA_VS,

	//------------------ dvi / hdmi ----------
	output wire [3:0] 	TMDS_P,
	output wire [3:0] 	TMDS_N,

	//------------------ ft812 spi and ctl ---
	inout wire 				FT_SPI_CS_N,
	inout wire 				FT_SPI_SCK,
	input wire 				FT_SPI_MISO,
	inout wire 				FT_SPI_MOSI,
	input wire 				FT_INT_N,
	input wire 				FT_CLK,
	input wire 				FT_DE,
	output wire 			FT_CLK_OUT,

	//------------------ cf card -------------
	output wire [2:0] 	WA,
	output wire [1:0] 	WCS_N,
	output wire 			WRD_N,
	output wire 			WWR_N,
	output wire 			WRESET_N,
	inout wire [15:0] 	WD,

	//------------------ analog in/out -------
	output wire 			TAPE_OUT,
	input wire 				TAPE_IN,

	//------------------ i2s dac -------------
	output wire          DAC_BCK,
	output wire          DAC_WS,
	output wire          DAC_DAT,

	//------------------ adc -----------------
	output wire 			ADC_CLK,
	inout wire 				ADC_BCK,
	inout wire 				ADC_LRCK,
	input wire 				ADC_DOUT,

	//------------------ esp32 i2s and cs ----
	inout wire           ESP32_SPI_CS_N,
	input wire           ESP32_PCM_BCK,
	input wire           ESP32_PCM_RLCK,
	input wire           ESP32_PCM_DAT,

	//------------------ mcu spi -------------
	input wire 				MCU_CS_N,
	input wire 				MCU_SCK,
	input wire 				MCU_MOSI,
	output wire 			MCU_MISO,
	inout wire [5:0] 		MCU_IO,  // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n

	//------------------ midi ----------------
	output wire 			MIDI_TX,

	//------------------ optional flash ------
	output wire 			FLASH_CS_N,
	input wire  			FLASH_DO,
	output wire 			FLASH_DI,
	output wire 			FLASH_SCK,
	output wire 			FLASH_WP_N,
	output wire 			FLASH_HOLD_N
);

// unused
assign FLASH_CS_N = 1'b1;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;
assign SD_CS_N = 1'b1;
assign SD_CLK = 1'b0;
assign SD_DI = 1'bz;
assign SD_DO = 1'bz;
assign WA = 3'd0;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b0;
assign WD = 16'hzzzz;
assign TAPE_OUT = 1'b0;
assign UART_CTS = 1'bz;
`ifdef UKNC_TEST_DQM
assign SDR_DQM = 2'b11;
`endif
`ifdef UKNC_TEST_NOUART
assign UART_TX = 1'b1;
`endif
assign MIDI_TX = 1'b1;
assign ESP32_SPI_CS_N = 1'b1;
assign ADC_CLK = 1'b0;
assign ADC_BCK = 1'bz;
assign ADC_LRCK = 1'bz;

// system clocks: VCO 400 MHz; 50 MHz memory / video (clk_ram), 4.17 MHz CPU, 50 MHz +56.25 degrees SDRAM clock,
// 25 MHz host (180 degrees: its falling edge on the PPU rising edge), 3.125 MHz PPU, 8 MHz (FT812, HDMI)
wire [5:0] pll_clk;
wire locked;
kg_pll #(
	.CLKFBOUT_MULT(8),
	.CLKOUT0_DIVIDE(8),
	.CLKOUT1_DIVIDE(96),
	.CLKOUT2_DIVIDE(8), .CLKOUT2_PHASE(56.25),
	.CLKOUT3_DIVIDE(16), .CLKOUT3_PHASE(180.0),
	.CLKOUT4_DIVIDE(128),
	.CLKOUT5_DIVIDE(50),
	.BUFG_MASK(6'b111110)
) pll (
	.clk_in		(CLK_50MHZ),
	.rst			(1'b0),
	.clk_out		(pll_clk),
	.locked		(locked)
);
// clk_ram: its PLL output without a BUFG also drives the BUFGMUX of the HDMI pll
wire clk_ram_pll = pll_clk[0];
wire clk_ram;
BUFG bufg_clk_ram(.I(clk_ram_pll), .O(clk_ram));
wire clk_cpu = pll_clk[1];
wire clk_sdr = pll_clk[2];
wire clk_host = pll_clk[3];
wire clk_ppu = pll_clk[4];
wire clk_8mhz = pll_clk[5];
wire areset = ~locked;

// the video clock: 40 MHz for the 800 x 600 @ 60 Hz output of the frame buffer (a second PLL from clk_ram);
// its PLL output without a BUFG also drives the BUFGMUX of the HDMI pll
wire [5:0] pll2_clk;
wire locked2;
kg_pll #(
	.IBUFG(0),
	.CLKFBOUT_MULT(8),
	.CLKOUT0_DIVIDE(10),
	.BUFG_MASK(6'b000000)
) pll2 (
	.clk_in		(clk_ram),
	.rst			(~locked),
	.clk_out		(pll2_clk),
	.locked		(locked2)
);
wire clk_vid_pll = pll2_clk[0];
wire clk_vid;
BUFG bufg_clk_vid(.I(clk_vid_pll), .O(clk_vid));

// ft clk 8mhz out: the FT812 must always have its clock, also when the core does not use it
ODDR2 u_ft_clk(.Q(FT_CLK_OUT), .C0(clk_8mhz), .C1(~clk_8mhz), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));
// sdram clock
ODDR2 sdr_clock(.Q(SDR_CLK), .C0(clk_sdr), .C1(~clk_sdr), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

//---------- MCU ------------
wire [7:0] hid_kb_status, hid_kb_dat0, hid_kb_dat1, hid_kb_dat2, hid_kb_dat3, hid_kb_dat4, hid_kb_dat5;
wire [7:0] ms_x, ms_y;
wire [2:0] ms_b;
wire ms_upd;
wire [15:0] softsw_command, osd_command;
wire [1:0] hw_btn;
wire mcu_busy;
wire dvi_only;
wire [7:0] img_mounted, img_data, img_result;
wire [63:0] img_size;
wire [8:0] img_data_addr;
wire [15:0] img_sum;
wire [23:0] img_q_di;
wire img_data_wr, img_result_wr, img_q_wr, img_q_ack;
wire [7:0] rtc_a, rtc_do;

// MCU_SCK on a global buffer (as tsconf / baseconf)
wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck(.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck(.I(mcu_sck_ibufg), .O(mcu_sck));

wire mcu_burst_ready;
assign MCU_IO[1] = mcu_burst_ready;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

wire mcu_ft_spi_on, mcu_ft_vga_on, mcu_ft_sck, mcu_ft_mosi, mcu_ft_cs_n;
assign FT_SPI_CS_N = mcu_ft_spi_on ? mcu_ft_cs_n : 1'b1;
assign FT_SPI_SCK = mcu_ft_spi_on ? mcu_sck_ibufg : 1'b0;
assign FT_SPI_MOSI = mcu_ft_spi_on ? mcu_ft_mosi : 1'b0;

kg_mcu #(
	.BURST_MAX_MHZ(16),
	.CS_FILTER(3),
	.ENABLE_RTC(1),
	.ENABLE_UART(0),
	.ENABLE_MATRIX(0),
	.ENABLE_DEBUG(0),
	.ENABLE_IMG(1),
	.ENABLE_FILE(0),
	.ENABLE_FT(1),
	.ENABLE_SD2(0)
) mcu(
	.CLK				(clk_host),
	.N_RESET			(locked),

	.MCU_MOSI		(MCU_MOSI),
	.MCU_MISO		(MCU_MISO),
	.MCU_SCK			(mcu_sck),
	.MCU_SS			(MCU_CS_N),

	.MCU_SPI_FT_SS	(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),
	.MCU_BURST_CS_N(MCU_IO[0]),
	.MCU_BURST_READY(mcu_burst_ready),

	.MS_X				(ms_x),
	.MS_Y				(ms_y),
	.MS_Z				(),
	.MS_B				(ms_b),
	.MS_UPD			(ms_upd),

	.KB_STATUS		(hid_kb_status),
	.KB_DAT0			(hid_kb_dat0),
	.KB_DAT1			(hid_kb_dat1),
	.KB_DAT2			(hid_kb_dat2),
	.KB_DAT3			(hid_kb_dat3),
	.KB_DAT4			(hid_kb_dat4),
	.KB_DAT5			(hid_kb_dat5),

	.KB_SCANCODE	(),
	.KB_SCANCODE_UPD(),
	.XT_SCANCODE	(),
	.XT_SCANCODE_UPD(),

	.JOY_L			(),
	.JOY_R			(),
	.BTNS				(hw_btn),

	.RTC_A			(rtc_a),
	.RTC_DI			(8'd0),
	.RTC_DO			(rtc_do),
	.RTC_CS			(1'b0),
	.RTC_WR_N		(1'b1),

	.UART_RX_DATA	(),
	.UART_RX_IDX	(),
	.UART_TX_DATA	(8'd0),
	.UART_TX_WR		(1'b0),
	.UART_TX_MODE	(1'b0),
	.UART_DLL		(8'd0),
	.UART_DLM		(8'd0),
	.UART_DLL_WR	(1'b0),
	.UART_DLM_WR	(1'b0),

	.ROMLOADER_ACTIVE(),
	.ROMLOAD_ADDR	(),
	.ROMLOAD_DATA	(),
	.ROMLOAD_WR		(),

	.SOFTSW_COMMAND(softsw_command),
	.OSD_COMMAND	(osd_command),

	.FT_SPI_ON		(mcu_ft_spi_on),
	.FT_VGA_ON		(mcu_ft_vga_on),
	.FT_SCK			(mcu_ft_sck),
	.FT_MISO			(FT_SPI_MISO),
	.FT_MOSI			(mcu_ft_mosi),
	.FT_CS_N			(mcu_ft_cs_n),
	.FT_RESET		(),

	.HWID				(),
	.CORE_BUILD		(),
	.FW_BUILD		(),
	.DVI_ONLY		(dvi_only),

	.SD2_MISO		(1'b1),
	.MATRIX_CMD		(24'd0),
	.MATRIX_CMD_WR	(1'b0),
	.DEBUG_ADDR		(16'd0),
	.DEBUG_DATA		(16'd0),
	.IMG_Q_WR		(img_q_wr),
	.IMG_Q_DI		(img_q_di),
	.IMG_Q_ACK		(img_q_ack),
	.IMG_MOUNTED	(img_mounted),
	.IMG_SIZE		(img_size),
	.IMG_DATA_WR	(img_data_wr),
	.IMG_DATA_ADDR	(img_data_addr),
	.IMG_DATA		(img_data),
	.IMG_RESULT_WR	(img_result_wr),
	.IMG_RESULT		(img_result),
	.IMG_SUM			(img_sum),
	.PS2_COMMAND	(16'h0000),
	.PS2_COMMAND_WR(1'b0),
	.ESP_UART_RX_DATA(8'h00),
	.ESP_UART_RX_WR(1'b0),
	.FLASHBOOT_START(1'b0),
	.FLASHBOOT_COREID(5'd0),
	.PRN_DATA		(8'h00),
	.PRN_WR			(1'b0),

	.BUSY				(mcu_busy)
);

//---------- image files of the mcu: FDD0-FDD3 slots 0-3, HDD0 slot 4 ------------
wire [7:0] sdc_mounted;
wire [63:0] sdc_size;
wire [4:0] sd_rd, sd_wr;
wire [31:0] sd_sector;
wire sd_busy, sd_done, sd_byte_strobe;
wire [8:0] sd_byte_index;
wire [7:0] sd_rd_data, sd_wr_data;

img_sdc #(.OUT_LATENCY(3), .TIMEOUT(24'd5000000)) img(
	.clk					(clk_host),
	.reset				(areset),
	.img_mounted		(img_mounted),
	.img_size			(img_size),
	.img_data_wr		(img_data_wr),
	.img_data_addr		(img_data_addr),
	.img_data			(img_data),
	.img_result_wr		(img_result_wr),
	.img_result			(img_result),
	.img_sum				(img_sum),
	.img_q_wr			(img_q_wr),
	.img_q_di			(img_q_di),
	.img_q_ack			(img_q_ack),
	.sdc_img_mounted	(sdc_mounted),
	.sdc_img_size		(sdc_size),
	.sdc_rd				({3'd0, sd_rd}),
	.sdc_wr				({3'd0, sd_wr}),
	.sdc_sector			(sd_sector),
	.sdc_busy			(sd_busy),
	.sdc_done			(sd_done),
	.sdc_error			(),
	.sdc_slot			(),
	.sdc_byte_in_strobe(sd_byte_strobe),
	.sdc_byte_addr		(sd_byte_index),
	.sdc_byte_in_data	(sd_rd_data),
	.sdc_byte_out_data(sd_wr_data)
);

`include "uknc_switches.vh"

//---------- Soft switches (core_minig.json "osd", in this order: register n = regs[n*8 +: 8]) ------------
wire [`UKNC_SW_N*8-1:0] softsw;
kg_soft_switches #(.N(`UKNC_SW_N), .INIT(`UKNC_SW_INIT)) soft_switches(
	.clk		(clk_host),
	.command	(softsw_command),
	.regs		(softsw),
	.upd		()
);
`include "uknc_switch_fields.vh"

//---------- the Kakave clock from the clock of the board ------------
wire [7:0] rtc_set_val;
wire rtc_set_tgl;
wire [2:0] rtc_set_field;
uknc_rtc_seed rtc_seed(
	.clk		(clk_host),
	.busy		(mcu_busy),
	.rtc_a	(rtc_a),
	.rtc_do	(rtc_do),
	.set_tgl	(rtc_set_tgl),
	.set_field(rtc_set_field),
	.set_val	(rtc_set_val)
);

//---------- Keyboard ------------
wire [7:0] keycode;
uknc_keyboard keyboard(
	.clk		(clk_host),
	.reset	(mcu_busy),
	.report	({hid_kb_dat5, hid_kb_dat4, hid_kb_dat3, hid_kb_dat2, hid_kb_dat1, hid_kb_dat0, hid_kb_status}),
	.keycode	(keycode)
);

//---------- the machine ------------

wire [2:0] red, green, blue;
wire hsync, vsync, visible;
wire [15:0] audio_l, audio_r;
wire i2s_bck, i2s_ws, i2s_din;

uknc #(.PHYS_FDD(0)) machine(
	.clkram				(clk_ram),
	.clk4					(clk_cpu),
	.clk_25				(clk_host),
	.clk_3_12			(clk_ppu),
	.locked				(locked),

	.sdram_a				(SDR_A[10:0]),
	.sdram_dq			(SDR_DQ),
	.sdram_ba			(SDR_BA),
`ifdef UKNC_TEST_DQM
	.sdram_dqm			(),
`else
	.sdram_dqm			(SDR_DQM),
`endif
	.sdram_cs_n			(),
	.sdram_we_n			(SDR_WE_N),
	.sdram_ras_n		(SDR_RAS_N),
	.sdram_cas_n		(SDR_CAS_N),

	.red					(red),
	.green				(green),
	.blue					(blue),
	.hsync				(hsync),
	.vsync				(vsync),
	.visible				(visible),

	.audio_l				(audio_l),
	.audio_r				(audio_r),
	.beeper				(),
	.i2s_bck				(i2s_bck),
	.i2s_ws				(i2s_ws),
	.i2s_din				(i2s_din),

	.host_busy			(mcu_busy),
	.reset				(sw_reset | hw_btn[0]),
	.keycode				(keycode),
	.mouse_tgl			(ms_upd),
	.mouse_dx			(ms_x),
	.mouse_dy			(ms_y),
	.mouse_btns			(ms_b[1:0]),

	.system_volume		(sw_volume),
	.system_floppy_wprot(sw_floppy_wprot),
	.system_hdd_mode	(sw_hdd_mode),
	.system_hdd_wprot	(sw_hdd_wprot),
	.system_hdd_delay	(sw_hdd_delay),
	.system_beeper		(sw_beeper),
	.system_ay_en		(sw_ay_en),
	.system_covox		(sw_covox),
	.system_stereo		(sw_stereo),
	.system_lowpass	(sw_lowpass),
	.system_oldfreaks	(sw_oldfreaks),
	.system_fdd_en		(sw_fdd_en),
	.system_hdd_en		(sw_hdd_en),
	.system_mouse_en	(sw_mouse_en),
	.system_rtc_en		(sw_rtc_en),
	.system_physical_fdd(3'd0),

	.rtc_set_tgl		(rtc_set_tgl),
	.rtc_set_field		(rtc_set_field),
	.rtc_set_val		(rtc_set_val),
	.rtc_year			(),
	.rtc_month			(),
	.rtc_date			(),
	.rtc_hour			(),
	.rtc_min				(),
	.rtc_sec				(),
	.rtc_dow				(),

	.sd_img_mounted	(sdc_mounted[4:0]),
	.sd_img_size		(sdc_size[31:0]),
	.sd_rd				(sd_rd),
	.sd_wr				(sd_wr),
	.sd_sector			(sd_sector),
	.sd_busy				(sd_busy),
	.sd_done				(sd_done),
	.sd_rd_byte_strobe(sd_byte_strobe),
	.sd_byte_index		(sd_byte_index),
	.sd_rd_data			(sd_rd_data),
	.sd_wr_data			(sd_wr_data),

	.uart_rx				(UART_RX),
`ifdef UKNC_TEST_NOUART
	.uart_tx				(),
`else
	.uart_tx				(UART_TX),
`endif

	.FDC_INDEX			(1'b0),
	.FDC_TR00			(1'b0),
	.FDC_WPRT			(1'b1),
	.FDC_RDATA			(1'b0),
	.FDC_DRIVE			(),
	.FDC_MOTOR			(),
	.FDC_DIR				(),
	.FDC_STEP			(),
	.FDC_WDATA			(),
	.FDC_WGATE			(),
	.FDC_SIDE_N			()
);
assign SDR_A[12:11] = 2'b00;

//--------- video: frame buffer in the SRAM, 800 x 600 @ 60 Hz out, OSD --------------
wire [2:0] red_m = sw_bgr ? blue : red;
wire [2:0] blue_m = sw_bgr ? red : blue;
wire [23:0] fb_rgb, osd_rgb;
wire fb_hs, fb_vs, fb_de;

uknc_framebuffer framebuffer(
	.clkram			(clk_ram),
	.red				(red_m),
	.green			(green),
	.blue				(blue_m),
	.vsync			(vsync),
	.visible			(visible),
	.sram_a			(MA),
	.sram_d			(MD),
	.sram_we_n		(MWR_N),
	.sram_oe_n		(MRD_N),
	.clk_vid			(clk_vid),
	.rgb				(fb_rgb),
	.hs				(fb_hs),
	.vs				(fb_vs),
	.de				(fb_de)
);

// the OSD commands of the mcu (host clock) into clk_vid: a value is taken when it is the same on two clocks
reg [15:0] osd_s1 = 16'd0, osd_s2 = 16'd0, osd_vid = 16'd0;
always @(posedge clk_vid) begin
	osd_s1 <= osd_command;
	osd_s2 <= osd_s1;
	if (osd_s1 == osd_s2) osd_vid <= osd_s2;
end

// the place of the OSD as in the menu core (the same 800 x 600 timing)
kg_osd_overlay #(.H_OFFSET(171), .V_OFFSET(60), .H_DIV4_WIDTH(1200)) overlay(
	.clk				(clk_vid),
	.rgb_i			(fb_rgb),
	.rgb_o			(osd_rgb),
	.hsync_i			(fb_hs),
	.vsync_i			(fb_vs),
	.osd_command	(osd_vid)
);

//--------- hdmi --------------
// the audio of the mixer (PPU clock) into clk_vid: a value is taken when it is the same on two clocks
reg [31:0] aud_s1 = 32'd0, aud_s2 = 32'd0, aud_vid = 32'd0;
always @(posedge clk_vid) begin
	aud_s1 <= {audio_l, audio_r};
	aud_s2 <= aud_s1;
	if (aud_s1 == aud_s2) aud_vid <= aud_s2;
end

// the pixel clock is clk_vid (40 MHz); the FT812 video is not used (ft_sel 0)
wire ft_clk_ibufg, ft_clk_int;
IBUFG ibufg_ft_clk(.I(FT_CLK), .O(ft_clk_ibufg));
BUFG bufg_ft_clk(.I(ft_clk_ibufg), .O(ft_clk_int));

kg_hdmi_ft #(.SAMPLERATE(48000), .CLKRATE(40000000), .REF_MHZ(8'd40)) hdmi_top(
	.clk				(ft_clk_int),
	.clk_ref			(clk_vid),
	.clk_ref_pll	(clk_vid_pll),
	.clk_8			(clk_8mhz),
	.reset			(~locked2),

	.vga_rgb			(osd_rgb),
	.vga_hs			(fb_hs),
	.vga_vs			(fb_vs),
	.vga_de			(fb_de),

	.ft_rgb			({VGA_R, VGA_G, VGA_B}),
	.ft_hs			(VGA_HS),
	.ft_vs			(VGA_VS),
	.ft_de			(FT_DE),

	.ft_sel			(1'b0),

	.audio_en		(~dvi_only),
	.audio_l			(aud_vid[31:16]),
	.audio_r			(aud_vid[15:0]),

	.tmds_p			(TMDS_P),
	.tmds_n			(TMDS_N),

	.freq				()
);

//--------- i2s DAC (PCM5102): the serializer of tang on the PPU clock --------------
// DIN / WS change on the PPU rising edge; the PCM5102 samples BCK rising: BCK inverted, half a cycle of setup / hold
ODDR2 dac_clock(.Q(DAC_BCK), .C0(i2s_bck), .C1(~i2s_bck), .CE(1'b1), .D0(1'b0), .D1(1'b1), .R(1'b0), .S(1'b0));
assign DAC_WS = i2s_ws;
assign DAC_DAT = i2s_din;

endmodule
