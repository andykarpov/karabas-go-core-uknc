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

//---------- MCU: link v2 (karabas-go-firmware docs/link_v2.md, kg_mcu2); INT on IO1 ------------
`include "uknc_switches.vh"
wire [55:0] hid_kbd;
wire [7:0] ms_x, ms_y, ms_b;
wire ms_wr;
wire [5:0] hw_btns;
wire [1:0] hw_btn = hw_btns[1:0];
wire mcu_busy;
wire dvi_only;
wire [`UKNC_SW_N*8-1:0] softsw;
wire [7:0] rtc_a, rtc_do;
// RTC address: the kept SETUP colors (uknc_setup_keep in the machine) or the Kakave clock seed
wire [7:0] seed_rtc_a, keep_rtc_a, keep_rtc_di;
wire keep_rtc_own, keep_rtc_wr;
assign rtc_a = keep_rtc_own ? keep_rtc_a : seed_rtc_a;
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;

// MCU_SCK on a global buffer (as tsconf / baseconf)
wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck(.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck(.I(mcu_sck_ibufg), .O(mcu_sck));

wire mcu_int;
assign MCU_IO[1] = mcu_int;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

wire mcu_ft_spi_on, mcu_ft_mosi, mcu_ft_cs_n;
assign FT_SPI_CS_N = mcu_ft_spi_on ? mcu_ft_cs_n : 1'b1;
assign FT_SPI_SCK = mcu_ft_spi_on ? mcu_sck_ibufg : 1'b0;
assign FT_SPI_MOSI = mcu_ft_spi_on ? mcu_ft_mosi : 1'b0;

//---------- image files of the mcu: FDD0-FDD3 slots 0-3, HDD0 slot 4 (the mounter of kg_mcu2) ------------
wire [7:0] sdc_mounted;
wire [63:0] sdc_size;
wire [4:0] sd_rd, sd_wr;
wire [31:0] sd_sector;
wire sd_busy, sd_done, sd_byte_strobe;
wire [8:0] sd_byte_index;
wire [7:0] sd_rd_data, sd_wr_data;

// clk_host 25 MHz: below 4 x the 16 MHz sck of spi_freq (the upper bound of kg_l2_link)
kg_mcu2 #(
	.SW_N(`UKNC_SW_N),
	.SW_INIT(`UKNC_SW_INIT),
	.CS_FILTER(3),
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),
	.IMG_OUT_LATENCY(3),
	.ENABLE_RTC(1),       // rtc_mode 1, registers 0C / 0D skipped as kg_mcu did (the SETUP colors at 14..20)
	.ENABLE_FT(1),
	.ENABLE_SD2(0)
) mcu(
	.CLK(clk_host),
	.N_RESET(locked),

	.MCU_SCK(mcu_sck),
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SS(MCU_CS_N),
	.MCU_INT(mcu_int),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),

	.SW(softsw), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(dvi_only), .CORE_BUILD(), .FW_BUILD(),
	.BUSY(mcu_busy), .BTNS(hw_btns), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

	.KBD(hid_kbd), .KBD_WR(), .PS2_CODE(), .PS2_KIND(), .PS2_WR(),
	.MS_X(ms_x), .MS_Y(ms_y), .MS_Z(), .MS_B(ms_b), .MS_WR(ms_wr),
	.JOY_L(), .JOY_R(), .JOY_WR(),
	.PS2_CMD(16'h0000), .PS2_CMD_WR(1'b0),

	.LD_KIND(), .LD_SLOT(), .LD_SIZE(), .LD_START(), .LD_ACTIVE(), .LD_END(),
	.LD_ADDR(), .LD_DATA(), .LD_WR(), .LD_READY(1'b1),

	.OSD_WR(osd_wr), .OSD_WADDR(osd_waddr), .OSD_WDATA(osd_wdata), .OSD_EN(osd_en),
	.OSD_FG(osd_fg), .OSD_BG(osd_bg), .OSD_ALPHA(osd_alpha), .OSD_PX(osd_px), .OSD_PY(osd_py),
	.OSD_PW(osd_pw), .OSD_PH(osd_ph), .OSD_PLACE(osd_place), .OSD_ZOOM(osd_zoom),

	.SDC_IMG_MOUNTED(sdc_mounted), .SDC_IMG_SIZE(sdc_size),
	.SDC_RD({3'd0, sd_rd}), .SDC_WR({3'd0, sd_wr}), .SDC_SECTOR(sd_sector),
	.SDC_BUSY(sd_busy), .SDC_DONE(sd_done), .SDC_ERROR(), .SDC_SLOT(),
	.SDC_BYTE_IN_STROBE(sd_byte_strobe), .SDC_BYTE_ADDR(sd_byte_index),
	.SDC_BYTE_IN_DATA(sd_rd_data), .SDC_BYTE_OUT_DATA(sd_wr_data),
	.IMG_WP(), .IMG_PHYS_WR(), .IMG_PHYS(), .IMG_FLUSH(), .FDD_CHNG_WR(), .FDD_CHNG(),
	.FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0), .IMG_ACTIVE(),

	.PORT_OUT_DATA(), .PORT_OUT_WR(), .PORT_OUT_READY(4'b1111), .PORT_IN_DATA(32'd0), .PORT_IN_WR(4'd0),
	.PORT_CFG(128'd0), .PORT_IN_FULL(), .PORT_STAT(), .PORT_STAT_WR(),
	.RTC_A(rtc_a), .RTC_DI(keep_rtc_di), .RTC_CS(keep_rtc_wr), .RTC_WR_N(~keep_rtc_wr), .RTC_DO(rtc_do),
	.MATRIX_CMD(24'd0), .MATRIX_CMD_WR(1'b0), .DEBUG_ADDR(16'd0), .DEBUG_DATA(16'd0),

	.FT_SPI_ON(mcu_ft_spi_on), .FT_VGA_ON(), .FT_RESET(), .FT_SCK(), .FT_MOSI(mcu_ft_mosi), .FT_MISO(FT_SPI_MISO),
	.FT_CS_N(mcu_ft_cs_n),
	.SD2_SCK(), .SD2_MOSI(), .SD2_MISO(1'b1), .SD2_CS_N()
);

// the mouse: the MS_WR pulse of v2 as the toggle of v1 (the machine takes a change of it)
reg ms_upd = 1'b0;
always @(posedge clk_host) if (ms_wr) ms_upd <= ~ms_upd;

// the OSD switches: the SW registers of kg_mcu2 (uknc_switches.vh, register n = softsw[n*8 +: 8])
`include "uknc_switch_fields.vh"

//---------- the Kakave clock from the clock of the board ------------
wire [7:0] rtc_set_val;
wire rtc_set_tgl;
wire [2:0] rtc_set_field;
uknc_rtc_seed rtc_seed(
	.clk		(clk_host),
	.busy		(mcu_busy),
	.rtc_a	(seed_rtc_a),
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
	.report	(hid_kbd),
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
	.sdram_dqm			(SDR_DQM),
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
	.system_cpu_slow	(sw_cpu_slow),

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
	.keep_rtc_own		(keep_rtc_own),
	.keep_rtc_a			(keep_rtc_a),
	.keep_rtc_di			(keep_rtc_di),
	.keep_rtc_wr			(keep_rtc_wr),
	.rtc_do				(rtc_do),

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
	.uart_tx				(UART_TX),

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

// the bitmap OSD of link v2 (kg_l2_osd_overlay): centred in de, the scale from its size,
// 2 clocks of latency with its syncs and de
wire osd_hs, osd_vs, osd_de;
kg_l2_osd_overlay osd(
	.wclk(clk_host),
	.osd_wr(osd_wr), .osd_waddr(osd_waddr), .osd_wdata(osd_wdata), .osd_en(osd_en),
	.osd_fg(osd_fg), .osd_bg(osd_bg), .osd_alpha(osd_alpha), .osd_px(osd_px), .osd_py(osd_py),
	.osd_pw(osd_pw), .osd_ph(osd_ph), .osd_place(osd_place), .osd_zoom(osd_zoom),
	.icon_on(8'd0), .icon_act(8'd0),
	.clk(clk_vid),
	.rgb_i(fb_rgb), .hs_i(fb_hs), .vs_i(fb_vs), .de_i(fb_de),
	.rgb_o(osd_rgb), .hs_o(osd_hs), .vs_o(osd_vs), .de_o(osd_de)
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
	.vga_hs			(osd_hs),
	.vga_vs			(osd_vs),
	.vga_de			(osd_de),

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
