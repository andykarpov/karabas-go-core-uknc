`timescale 1ns / 1ps
`default_nettype wire
/*
 The UKNC (Elektronika MS-0511) machine of tang-uknc (tang/src/top.v, (c) Alexey Gurov, Sergei Lemeshev, MIT)
 without the host of the Tang Nano board (BL616 SPI, sysctrl, sd_card, OSD, HDMI, flash, core loader): the CPU and
 the PPU (two 1801VM2), ROM, the SDRAM / video arbiter (sdram2), four floppies, the IDE cartridge with WD ROM,
 keyboard controller, Kakave mouse / RTC, the Aberrant three AYs, beeper, both Covox ports, mixer, C2 UART.

 The port to Karabas (Sergei Lemeshev, karabas-forge mc0511, 2026): PLL clocks for the machine (the Tang top took
 clk_25 / clk_3_12 from counter bits of sdram2), the memory phase aligned to the PPU clock, the PPU held in reset
 while the MCU is busy, the size of the HDD image for the IDE bounds, the physical floppy of the Go.

 The host side is in the board tops: kg_mcu, img_sdc (the sector interface below), the OSD, the switches.
*/

module uknc #(
	parameter PHYS_FDD = 1           // the Go has the floppy connector
) (
	input wire clkram,               // 50 MHz: SDRAM, video
	input wire clk4,                 // 4.17 MHz: CPU
	input wire clk_25,               // 25 MHz, 180 degrees: host side, floppies, IDE
	input wire clk_3_12,             // 3.125 MHz: PPU
	input wire locked,

	// SDRAM (11 bit address: the low rows of the 13 bit chip)
	output wire [10:0] sdram_a,
	inout wire [15:0] sdram_dq,
	output wire [1:0] sdram_ba,
	output wire [1:0] sdram_dqm,
	output wire sdram_cs_n,
	output wire sdram_we_n,
	output wire sdram_ras_n,
	output wire sdram_cas_n,

	// video (clkram)
	output wire [2:0] red,
	output wire [2:0] green,
	output wire [2:0] blue,
	output wire hsync,
	output wire vsync,
	output wire visible,

	// audio
	output wire [15:0] audio_l,
	output wire [15:0] audio_r,
	output wire beeper,
	output wire i2s_bck,             // the I2S of tang (PPU clock), the Go / Mini G PCM5102
	output wire i2s_ws,
	output wire i2s_din,

	// host (clk_25)
	input wire host_busy,            // the MCU loads the core / sets up: PPU held in reset
	input wire reset,                // OSD Reset, F12, the board button
	input wire [7:0] keycode,        // UKNC scan code (uknc_keyboard)
	input wire mouse_tgl,
	input wire [7:0] mouse_dx,
	input wire [7:0] mouse_dy,
	input wire [1:0] mouse_btns,

	// switches (clk_25)
	input wire [1:0] system_volume,
	input wire [3:0] system_floppy_wprot,
	input wire [1:0] system_hdd_mode,
	input wire system_hdd_wprot,
	input wire [5:0] system_hdd_delay,
	input wire system_beeper,
	input wire [2:0] system_ay_en,
	input wire [1:0] system_covox,
	input wire system_stereo,
	input wire system_lowpass,
	input wire system_oldfreaks,
	input wire system_fdd_en,
	input wire system_hdd_en,
	input wire system_mouse_en,
	input wire system_rtc_en,
	input wire [2:0] system_physical_fdd,
	input wire [2:0] system_cpu_slow,    // CPU speed: 0 full, 1..7 = 1/2, 1/2.5, 1/3, 1/3.5, 1/4, 1/5, 1/6

	// RTC set (a toggle per field: 0 year-2020, 1 month-1, 2 day-1, 3 hour, 4 minute, 5 second) and its time
	input wire rtc_set_tgl,
	input wire [2:0] rtc_set_field,
	input wire [7:0] rtc_set_val,
	output wire [15:0] rtc_year,
	output wire [3:0] rtc_month,
	output wire [4:0] rtc_date,
	output wire [4:0] rtc_hour,
	output wire [5:0] rtc_min,
	output wire [5:0] rtc_sec,
	output wire [3:0] rtc_dow,

	// the SETUP colors kept in the DS1307 registers 14..20 of kg_mcu (clk_25, uknc_setup_keep): rtc_own = these
	// drive the RTC address (else uknc_rtc_seed), rtc_wr a write of one clock (RTC_CS, !RTC_WR_N)
	output wire keep_rtc_own,
	output wire [7:0] keep_rtc_a,
	output wire [7:0] keep_rtc_di,
	output wire keep_rtc_wr,
	input wire [7:0] rtc_do,

	// image sectors (clk_25, img_sdc): slots 0-3 the floppies, 4 the IDE disk
	input wire [4:0] sd_img_mounted,
	input wire [31:0] sd_img_size,
	output wire [4:0] sd_rd,
	output wire [4:0] sd_wr,
	output wire [31:0] sd_sector,
	input wire sd_busy,
	input wire sd_done,
	input wire sd_rd_byte_strobe,
	input wire [8:0] sd_byte_index,
	input wire [7:0] sd_rd_data,
	output wire [7:0] sd_wr_data,

	// C2 serial port
	input wire uart_rx,
	output wire uart_tx,

	// physical floppy (Go)
	input wire FDC_INDEX,
	input wire FDC_TR00,
	input wire FDC_WPRT,
	input wire FDC_RDATA,
	output wire [1:0] FDC_DRIVE,
	output wire FDC_MOTOR,
	output wire FDC_DIR,
	output wire FDC_STEP,
	output wire FDC_WDATA,
	output wire FDC_WGATE,
	output wire FDC_SIDE_N
);

wire cpuclk_p = clk4, cpuclk_n = ~clk4;
wire ppuclk_p = clk_3_12, ppuclk_n = ~clk_3_12;
wire clk_50 = clkram;
wire init;

//------------------------------------------------------------//
// Start the memory phase counter at the first PPU rising edge after lock.
// Sampling on the opposite 50 MHz edge gives the PLL clocks half a cycle
// to settle; the next positive edge advances phase 8 to phase 9.
reg ppu_edge = 0, ppu_previous = 0, memory_aligned = 0;
always @(posedge clk_3_12) if (!locked) ppu_edge <= 0; else ppu_edge <= ~ppu_edge;
always @(negedge clkram) begin
	ppu_previous <= ppu_edge;
	if (!locked) memory_aligned <= 0;
	else if (ppu_edge != ppu_previous) memory_aligned <= 1;
end

//------------------------------------------------------------//
// RAM cpu/ppu
//------------------------------------------------------------//
wire [15:0] addr_cpu_o;
wire [31:0] data_cpu_i;
wire [31:0] data_cpu_o;
wire read_cpu_o;
wire wrte_cpu_o;
wire [3:0] mask_cpu_o;
wire askn_cpu_i;

wire [15:0] addr_ppu_o;
wire [31:0] data_ppu_i;
wire [31:0] data_ppu_o;
wire read_ppu_o;
wire wrte_ppu_o;
wire [3:0] mask_ppu_o;
wire askn_ppu_i;

sdram2 ram1(
	.SDRAM_A    (sdram_a),
	.SDRAM_DQr  (sdram_dq),
	.SDRAM_BA   (sdram_ba),
	.SDRAM_nCS  (sdram_cs_n),
	.SDRAM_nWE  (sdram_we_n),
	.SDRAM_nRAS (sdram_ras_n),
	.SDRAM_nCAS (sdram_cas_n),
	.SDRAM_DQML (sdram_dqm[0]),
	.SDRAM_DQMH (sdram_dqm[1]),

	.clkram     (clkram),
	.lockclk    (memory_aligned),
	.init       (init),

	.hsync      (hsync),
	.vsync      (vsync),
	.visible    (visible),
	.red        (red),
	.green      (green),
	.blue       (blue),

	.clk_25     (),                // counter bits of the Tang top: the PLL gives these clocks
	.clk_50     (),

	.cpu_addr   ({3'd0, addr_cpu_o}),
	.cpu_dout   (data_cpu_i),
	.cpu_din    (data_cpu_o),
	.cpu_dqm    (mask_cpu_o),
	.cpu_read   (read_cpu_o),
	.cpu_wrte   (wrte_cpu_o),
	.cpu_busy   (),
	.cpu_asck   (askn_cpu_i),

	.ppu_clk    (),
	.ppu_addr   ({3'd0, addr_ppu_o}),
	.ppu_dout   (data_ppu_i),
	.ppu_din    (data_ppu_o),
	.ppu_dqm    (mask_ppu_o),
	.ppu_read   (read_ppu_o),
	.ppu_wrte   (wrte_ppu_o),
	.ppu_busy   (),
	.ppu_asck   (askn_ppu_i)
);

//------------------------------------------------------------//
// mounted images: sd_img_mounted[n] is a one-cycle pulse with the size of slot n
reg [4:0] mount_dsk = 5'b00000;
reg [31:0] hdd_sectors = 32'd0;
integer mount_i;
always @(posedge clk_25) begin
	for (mount_i = 0; mount_i < 5; mount_i = mount_i + 1)
		if (sd_img_mounted[mount_i]) mount_dsk[mount_i] <= |sd_img_size;
	if (sd_img_mounted[4]) hdd_sectors <= sd_img_size >> 9;
end

//------------------------------------------------------------//
//  Wishbone PPU
//------------------------------------------------------------//
wire ppu_vm_init_o;
wire ppu_vm_virq_i;

wire [16:0] ppu_wbm_adr_o;
wire [15:0] ppu_wbm_dat_o;
wire [15:0] ppu_wbm_dat_i;
wire ppu_wbm_cyc_o;
wire ppu_wbm_wre_o;
wire [1:0] ppu_wbm_sel_o;
wire ppu_wbm_stb_o;
wire ppu_wbm_ack_i;
wire [15:0] ppu_wbi_dat_i;
wire ppu_wbi_ack_i;
wire ppu_wbi_stb_o;

// vp1-120
wire ppu_vm_virq_i_vp;
wire [15:0] ppu_wbm_dat_i_vp;
wire ppu_wbm_ack_i_vp;
wire [15:0] ppu_wbi_dat_i_vp;
wire ppu_wbi_ack_i_vp;
wire pin_tmr_ena_o;
// vp1-128
wire [15:0] ppu_wbm_dat_i_128;
wire ppu_wbm_ack_i_128;
// xm2-01
wire [15:0] ppu_wbm_dat_i_xm2;
wire ppu_vm_virq_i_xm2;
wire ppu_wbm_ack_i_xm2;
wire [15:0] ppu_wbi_dat_i_xm2;
wire ppu_wbi_ack_i_xm2;
wire ppu_wbi_stb_o_xm2;
// aberrant
wire [15:0] ppu_wbm_dat_i_abr;
wire ppu_wbm_ack_i_abr;
// covox
wire [15:0] ppu_wbm_dat_i_cvx;
wire ppu_wbm_ack_i_cvx;
// kakave+ mouse and RTC
wire [15:0] ppu_wbm_dat_i_kkv;
wire ppu_wbm_ack_i_kkv;
// ide
wire [15:0] ppu_wbm_dat_i_ide;
wire ppu_wbm_ack_i_ide;

assign ppu_vm_virq_i = ppu_vm_virq_i_xm2 | ppu_vm_virq_i_vp;

assign ppu_wbm_dat_i = ppu_wbm_ack_i_xm2 ? ppu_wbm_dat_i_xm2 :
                       ppu_wbm_ack_i_vp  ? ppu_wbm_dat_i_vp  :
                       ppu_wbm_ack_i_128 ? ppu_wbm_dat_i_128 :
                       ppu_wbm_ack_i_abr ? ppu_wbm_dat_i_abr :
                       ppu_wbm_ack_i_cvx ? ppu_wbm_dat_i_cvx :
                       ppu_wbm_ack_i_kkv ? ppu_wbm_dat_i_kkv :
                       ppu_wbm_ack_i_ide ? ppu_wbm_dat_i_ide : 16'o0;

assign ppu_wbm_ack_i = ppu_wbm_ack_i_xm2 | ppu_wbm_ack_i_vp | ppu_wbm_ack_i_128 | ppu_wbm_ack_i_abr |
                       ppu_wbm_ack_i_cvx | ppu_wbm_ack_i_kkv | ppu_wbm_ack_i_ide;

assign ppu_wbi_dat_i = ppu_wbi_ack_i_xm2 ? ppu_wbi_dat_i_xm2 :
                       ppu_wbi_ack_i_vp  ? ppu_wbi_dat_i_vp  : 16'o0;
assign ppu_wbi_ack_i = ppu_wbi_ack_i_xm2 | ppu_wbi_ack_i_vp;

//------------------------------------------------------------//
//  Wishbone CPU
//------------------------------------------------------------//
wire [15:0] vp65_wbm_dat_i;
wire [15:0] vp65_wbi_dat_i;
wire vp65_vm_virq_i;
wire vp65_wbm_ack_i;
wire vp65_wbi_ack_i;

wire cpu_vm_init_o;
wire cpu_vm_dclo_i;
wire cpu_vm_aclo_i;
wire pin_vm_halt_i;

// vp1-120
wire cpu_vm_virq_i_vp;
wire [15:0] cpu_wbm_dat_i_vp;
wire cpu_wbm_ack_i_vp;
wire [15:0] cpu_wbi_dat_i_vp;
wire cpu_wbi_ack_i_vp;

wire cpu_vm_virq_i = cpu_vm_virq_i_vp | vp65_vm_virq_i;

wire [16:0] cpu_wbm_adr_o;
wire [15:0] cpu_wbm_dat_o;
wire cpu_wbm_ack_i = cpu_wbm_ack_i_vp | vp65_wbm_ack_i;
wire [15:0] cpu_wbm_dat_i = cpu_wbm_ack_i_vp ? cpu_wbm_dat_i_vp :
                            vp65_wbm_ack_i   ? vp65_wbm_dat_i   : 16'o0;
wire cpu_wbm_cyc_o;
wire cpu_wbm_wre_o;
wire [1:0] cpu_wbm_sel_o;
wire cpu_wbm_stb_o;
wire [15:0] cpu_wbi_dat_i = cpu_wbi_ack_i_vp ? cpu_wbi_dat_i_vp :
                            vp65_wbi_ack_i   ? vp65_wbi_dat_i   : 16'o0;
wire cpu_wbi_ack_i = cpu_wbi_ack_i_vp | vp65_wbi_ack_i;
wire cpu_wbi_stb_o;

//------------------------------------------------------------//
// The PPU is held until the memory is initialised (tang) and while the MCU is busy (the port).
wire cart_sel;
wire [1:0] cart_bank;
wire pp_rst = reset | host_busy | ~init;
wire ppu_rom, ppu_rom_ovr;
wire [15:0] ppu_rom_ovr_dat;

ppu_wb ppu1(
	.clk_ppu_p      (ppuclk_p),
	.clk_ppu_n      (ppuclk_n),
	.rst            (pp_rst),
	.clk50hz        (vsync),

	.addr_ram       (addr_ppu_o),
	.duot_ram       (data_ppu_o),
	.dinp_ram       (data_ppu_i),
	.mask_ram       (mask_ppu_o),
	.read_ram       (read_ppu_o),
	.wrte_ram       (wrte_ppu_o),
	.askn_ram       (askn_ppu_i),

	.pin_vm_init_o  (ppu_vm_init_o),
	.pin_vm_dclo_o  (),             // the PPU's own DCLO/ACLO go nowhere;
	.pin_vm_aclo_o  (),             // the CPU's come from xm2_01's R177716

	.pin_vm_virq_i  (ppu_vm_virq_i),

	.pin_wbm_adr_o  (ppu_wbm_adr_o),
	.pin_wbm_dat_o  (ppu_wbm_dat_o),
	.pin_wbm_dat_i  (ppu_wbm_dat_i),
	.pin_wbm_cyc_o  (ppu_wbm_cyc_o),
	.pin_wbm_wre_o  (ppu_wbm_wre_o),
	.pin_wbm_sel_o  (ppu_wbm_sel_o),
	.pin_wbm_stb_o  (ppu_wbm_stb_o),
	.pin_wbm_ack_i  (ppu_wbm_ack_i),
	.pin_wbi_dat_i  (ppu_wbi_dat_i),
	.pin_wbi_ack_i  (ppu_wbi_ack_i),
	.pin_wbi_stb_o  (ppu_wbi_stb_o),

	.pin_tmr_ena_o  (pin_tmr_ena_o),
	.pin_cart_sel_o (cart_sel),
	.pin_cart_bank_o(cart_bank),

	.pin_rom_o        (ppu_rom),
	.pin_rom_ovr_i    (ppu_rom_ovr),
	.pin_rom_ovr_dat_i(ppu_rom_ovr_dat)
);

// the colors of the SETUP menu (F7) over resets and power off
uknc_setup_keep setup_keep(
	.ppu_clk     (ppuclk_p),
	.ppu_adr     (ppu_wbm_adr_o[15:0]),
	.ppu_we      (ppu_wbm_wre_o),
	.ppu_stb     (ppu_wbm_stb_o),
	.ppu_sel     (ppu_wbm_sel_o),
	.ppu_dat     (ppu_wbm_dat_o),
	.ppu_rom     (ppu_rom),
	.rom_ovr     (ppu_rom_ovr),
	.rom_ovr_dat (ppu_rom_ovr_dat),

	.clk         (clk_25),
	.busy        (host_busy),
	.rtc_own     (keep_rtc_own),
	.rtc_a       (keep_rtc_a),
	.rtc_di      (keep_rtc_di),
	.rtc_wr      (keep_rtc_wr),
	.rtc_do      (rtc_do)
);

//------------------------------------------------------------//
wire sound;
assign beeper = sound & system_beeper;

xm2_01 dd1(
	.pin_vm_clk25 (clk_25),
	.pin_vm_clk_p (ppuclk_n),

	.pin_vm_init_i(ppu_vm_init_o),
	.pin_vm_virq_o(ppu_vm_virq_i_xm2),

	.pin_wbm_adr_i(ppu_wbm_adr_o),
	.pin_wbm_dat_i(ppu_wbm_dat_o),
	.pin_wbm_dat_o(ppu_wbm_dat_i_xm2),
	.pin_wbm_wre_i(ppu_wbm_wre_o),
	.pin_wbm_stb_i(ppu_wbm_stb_o),
	.pin_wbm_ack_o(ppu_wbm_ack_i_xm2),

	.pin_wbi_dat_o(ppu_wbi_dat_i_xm2),
	.pin_wbi_ack_o(ppu_wbi_ack_i_xm2),
	.pin_wbi_stb_i(ppu_wbi_stb_o),

	.pin_vm_dclo_o(cpu_vm_dclo_i),
	.pin_vm_aclo_o(cpu_vm_aclo_i),
	.pin_vm_halt_o(pin_vm_halt_i),

	.pin_wbi_stb_o(ppu_wbi_stb_o_xm2),

	.but_data     (keycode),

	.sound        (sound)
);

// DCLO, ACLO and HALT of the CPU (R177716, PPU domain) through two flops on the CPU clock (tang).
reg [1:0] cpu_dclo_s = 2'b11;
reg [1:0] cpu_aclo_s = 2'b11;
reg [1:0] cpu_halt_s = 2'b00;
always @(posedge cpuclk_p) begin
	cpu_dclo_s <= {cpu_dclo_s[0], cpu_vm_dclo_i};
	cpu_aclo_s <= {cpu_aclo_s[0], cpu_vm_aclo_i};
	cpu_halt_s <= {cpu_halt_s[0], pin_vm_halt_i};
end

//------------------------------------------------------------//
// floppies: four image drives (fdd4) and the physical drive of the Go in place of one of them
wire [15:0] disk_data_out;
wire [15:0] disk_data_in;
wire [1:0] disk_drive;
wire disk_valid;
wire disk_sync;
wire disk_crc_ok;
wire disk_rdy;
wire disk_tr0;
wire disk_ind;
wire disk_motor;
wire disk_step;
wire disk_dir;
wire disk_head;
wire disk_write;

wire [3:0] fdd_rd, fdd_wr;
wire [31:0] fdd_sector;
wire [7:0] fdd_wr_data;
wire fdd_taken, fdd_outen;

wire physical_selected = PHYS_FDD && system_physical_fdd >= 1 && system_physical_fdd <= 4 &&
                         {1'b0, disk_drive} == system_physical_fdd - 3'd1;
wire [15:0] virtual_fdd_data, physical_fdd_data;
wire [3:0] image_fdd_rd, image_fdd_wr;
assign fdd_rd = (physical_selected || !system_fdd_en) ? 4'd0 : image_fdd_rd;
assign fdd_wr = (physical_selected || !system_fdd_en) ? 4'd0 : image_fdd_wr;
assign ppu_wbm_dat_i_128 = physical_selected ? physical_fdd_data : virtual_fdd_data;

generate if (PHYS_FDD) begin : phys
uknc_physical_fdd physical_fdd(
	.clk          (clk_25),
	.reset        (ppu_vm_init_o || host_busy || !locked || !system_fdd_en),
	.selected     (physical_selected),
	.motor        (disk_motor),
	.step         (disk_step),
	.dir          (disk_dir),
	.head         (disk_head),
	.write_protect(system_floppy_wprot[disk_drive]),
	.bus_addr     (ppu_wbm_adr_o),
	.bus_data     (ppu_wbm_dat_o),
	.bus_stb      (ppu_wbm_stb_o),
	.bus_write    (ppu_wbm_wre_o),
	.bus_ack      (ppu_wbm_ack_i_128),
	.bus_out      (physical_fdd_data),
	.index_in     (FDC_INDEX),
	.track0_in    (FDC_TR00),
	.protect_in   (FDC_WPRT),
	.rdata_in     (FDC_RDATA),
	.drive_out    (FDC_DRIVE),
	.motor_out    (FDC_MOTOR),
	.dir_out      (FDC_DIR),
	.step_out     (FDC_STEP),
	.side_out     (FDC_SIDE_N),
	.wgate_out    (FDC_WGATE),
	.wdata_out    (FDC_WDATA)
);
end else begin : no_phys
assign physical_fdd_data = 16'd0;
assign FDC_DRIVE = 2'b00;
assign FDC_MOTOR = 1'b0;
assign FDC_DIR = 1'b0;
assign FDC_STEP = 1'b0;
assign FDC_SIDE_N = 1'b0;
assign FDC_WGATE = 1'b0;
assign FDC_WDATA = 1'b0;
end endgenerate

fdd4 fdd(
	.pin_25mhz_ck (clk_25),
	.ppu_vm_init_i(ppu_vm_init_o),

	.data_in      (disk_data_in),
	.data_out     (disk_data_out),
	.write        (disk_write && !physical_selected && system_fdd_en && !system_floppy_wprot[disk_drive]),

	.drive        (disk_drive),
	.motor        (disk_motor && !physical_selected && system_fdd_en),
	.step         (disk_step && !physical_selected && system_fdd_en),
	.dir          (disk_dir),
	.head         (disk_head),
	.valid        (disk_valid),
	.sync         (disk_sync),
	.crc_ok       (disk_crc_ok),
	.rdy          (disk_rdy),
	.tr0          (disk_tr0),
	.ind          (disk_ind),

	.led_init     (),

	.rstart       (image_fdd_rd),
	.wstart       (image_fdd_wr),
	.rsector      (fdd_sector),
	.rbusy        (sd_busy),
	.rdone        (sd_done),

	.outen        (fdd_outen),
	.outaddr      (sd_byte_index),
	.inbyte       (sd_rd_data),
	.outbyte      (fdd_wr_data),
	.mount_dsk    (mount_dsk[3:0]),
	.sd_taken     (fdd_taken)
);

//------------------------------------------------------------//
// The IDE hard disk cartridge, slot 4; sd_arbiter gives the sector path to one owner at a time (tang).
wire hdd_sd_active;
wire hdd_rstart, hdd_wstart, hdd_other, hdd_outen;
wire [31:0] hdd_sector;
wire [7:0] hdd_wr_data;
wire sd_owner_hdd;

// the geometry of the image, from its sector 0 (the firmware of karabas-forge sent it as switches 240-244)
wire geo_active, geo_rd, geo_valid, hdd_inv;
wire [7:0] hdd_spt, hdd_heads;
wire [15:0] hdd_cyl;
uknc_hdd_geometry geometry(
	.clk         (clk_25),
	.mounted     (sd_img_mounted[4]),
	.size        (sd_img_size),
	.probe_active(geo_active),
	.probe_rd    (geo_rd),
	.owner       (sd_owner_hdd),
	.sd_busy     (sd_busy),
	.sd_done     (sd_done),
	.outen       (hdd_outen),
	.addr        (sd_byte_index),
	.data        (sd_rd_data),
	.valid       (geo_valid),
	.spt         (hdd_spt),
	.heads       (hdd_heads),
	.inv         (hdd_inv),
	.cyl         (hdd_cyl)
);

sd_arbiter sdarb(
	.clk        (clk_25),
	.fdd_rd     (fdd_rd),
	.fdd_wr     (fdd_wr),
	.fdd_sector (fdd_sector),
	.fdd_wr_data(fdd_wr_data),
	.fdd_taken  (fdd_taken),
	.fdd_outen  (fdd_outen),
	.hdd_rd     (geo_active ? geo_rd : hdd_rstart),
	.hdd_wr     (geo_active ? 1'b0 : hdd_wstart),
	.hdd_sector (geo_active ? 32'd0 : hdd_sector),
	.hdd_wr_data(hdd_wr_data),
	.hdd_other  (hdd_other),
	.hdd_outen  (hdd_outen),
	.sd_rd      (sd_rd),
	.sd_wr      (sd_wr),
	.sd_sector  (sd_sector),
	.sd_wr_data (sd_wr_data),
	.sd_busy    (sd_busy),
	.sd_done    (sd_done),
	.sd_outen   (sd_rd_byte_strobe),
	.owner_hdd  (sd_owner_hdd)
);

ide hdd(
	.clk          (clk_25),
	.rst          (ppu_vm_init_o),

	.wbm_adr_i    (ppu_wbm_adr_o),
	.wbm_dat_i    (ppu_wbm_dat_o),
	.wbm_dat_o    (ppu_wbm_dat_i_ide),
	.wbm_wre_i    (ppu_wbm_wre_o),
	.wbm_sel_i    (ppu_wbm_sel_o),
	.wbm_stb_i    (ppu_wbm_stb_o),
	.wbm_ack_o    (ppu_wbm_ack_i_ide),

	.cart_sel     (cart_sel),
	.cart_bank    (cart_bank),

	.hdd_present  (mount_dsk[4] & system_hdd_en & geo_valid),
	.image_sectors(hdd_sectors),
	.geo_spt      (hdd_spt),
	.geo_heads    (hdd_heads),
	.geo_inv      (hdd_inv),
	.geo_mode     (system_hdd_mode),
	.geo_cyl      (hdd_cyl),
	.wprot        (system_hdd_wprot),
	.hdd_delay    (system_hdd_delay),

	.sd_rstart    (hdd_rstart),
	.sd_wstart    (hdd_wstart),
	.sd_sector    (hdd_sector),
	.sd_rbusy     (sd_busy),
	.sd_rdone     (sd_done),
	.sd_other     (hdd_other),
	.sd_outen     (hdd_outen),
	.sd_outaddr   (sd_byte_index),
	.sd_inbyte    (sd_rd_data),
	.sd_outbyte   (hdd_wr_data),
	.sd_active    (hdd_sd_active)
);

vp1_128fdd vp128(
	.ppu_vm_clk_p (ppuclk_n),
	.ppu_vm_init_i(ppu_vm_init_o),

	.ppu_wbm_adr_i(ppu_wbm_adr_o),
	.ppu_wbm_dat_i(ppu_wbm_dat_o),
	.ppu_wbm_dat_o(virtual_fdd_data),
	.ppu_wbm_cyc_i(ppu_wbm_cyc_o),
	.ppu_wbm_wre_i(ppu_wbm_wre_o),
	.ppu_wbm_stb_i(ppu_wbm_stb_o),
	.ppu_wbm_ack_o(ppu_wbm_ack_i_128),

	.data_in      (disk_data_out),
	.data_out     (disk_data_in),
	.write        (disk_write),

	.drive        (disk_drive),
	.motor        (disk_motor),
	.step         (disk_step),
	.dir          (disk_dir),
	.head         (disk_head),
	.valid        (disk_valid),
	.sync         (disk_sync),
	.crc_ok       (disk_crc_ok),
	.rdy          (disk_rdy),
	.tr0          (disk_tr0),
	.ind          (disk_ind),
	.wrprt_dsk    (system_floppy_wprot),
	.fdd_en       (system_fdd_en)
);

//------------------------------------------------------------//
wire [9:0] ay_a_channel;    // A, B and C of the three chips, each summed
wire [9:0] ay_b_channel;    // across the chips in aberrant - the mixer
wire [9:0] ay_c_channel;    // below pans them

aberrant ay1(
	.ppu_vm_clk_p (ppuclk_n),
	.ppu_vm_init_i(ppu_vm_init_o),

	.ppu_wbm_adr_i(ppu_wbm_adr_o),
	.ppu_wbm_dat_i(ppu_wbm_dat_o),
	.ppu_wbm_dat_o(ppu_wbm_dat_i_abr),
	.ppu_wbm_cyc_i(ppu_wbm_cyc_o),
	.ppu_wbm_wre_i(ppu_wbm_wre_o),
	.ppu_wbm_sel_o(ppu_wbm_sel_o),
	.ppu_wbm_stb_i(ppu_wbm_stb_o),
	.ppu_wbm_ack_o(ppu_wbm_ack_i_abr),

	.ay_en        (system_ay_en),

	.a_channel    (ay_a_channel),
	.b_channel    (ay_b_channel),
	.c_channel    (ay_c_channel),
	.m_channel    ()
);

// The 8-bit DAC at 0177372, the Covox of the Aberrant's map.
wire [7:0] covox_sample;

covox cvx1(
	.clk   (ppuclk_n),
	.init  (ppu_vm_init_o),
	.en    (system_covox[0]),       // Port 177372 or Both
	.adr   (ppu_wbm_adr_o),
	.dat_i (ppu_wbm_dat_o),
	.dat_o (ppu_wbm_dat_i_cvx),
	.wre   (ppu_wbm_wre_o),
	.sel   (ppu_wbm_sel_o),
	.stb   (ppu_wbm_stb_o),
	.ack   (ppu_wbm_ack_i_cvx),
	.sample(covox_sample)
);

// The Kakave+ cartridge: mouse (0177400) and real-time clock (0177410). Neither reset touches the time.
kakave kkv1(
	.clk          (ppuclk_n),
	.init         (ppu_vm_init_o),
	.adr          (ppu_wbm_adr_o),
	.dat_i        (ppu_wbm_dat_o),
	.dat_o        (ppu_wbm_dat_i_kkv),
	.wre          (ppu_wbm_wre_o),
	.sel          (ppu_wbm_sel_o),
	.stb          (ppu_wbm_stb_o),
	.ack          (ppu_wbm_ack_i_kkv),
	.mouse_tgl    (mouse_tgl),
	.mouse_dx     (mouse_dx),
	.mouse_dy     (mouse_dy),
	.mouse_btns   (mouse_btns),
	.mouse_present(1'b1),
	.set_tgl      (rtc_set_tgl),
	.set_field    (rtc_set_field),
	.set_val      (rtc_set_val),
	.mouse_en     (system_mouse_en),
	.rtc_en       (system_rtc_en),
	.rtc_year     (rtc_year),
	.rtc_month    (rtc_month),
	.rtc_date     (rtc_date),
	.rtc_hour     (rtc_hour),
	.rtc_min      (rtc_min),
	.rtc_sec      (rtc_sec),
	.rtc_dow      (rtc_dow)
);

//------------------------------------------------------------//
//------------------------------------------------------------//
// CPU slowdown (OSD CPU speed): the slow clock mode of vm2_wb with a strobe every 2, 2.5 .. 6 clocks
// (a phase accumulator of half clocks: +2 per clock, a strobe and -period2 when it reaches period2), so the CPU
// runs that many times slower on average. The switch comes from the host clock: two flip-flops (it is static).
reg [2:0] cpu_slow_s1 = 3'd0, cpu_slow_s2 = 3'd0;
reg [3:0] cpu_acc = 4'd0;
reg cpu_clk_ena = 1'b0;
wire cpu_slow = cpu_slow_s2 != 3'd0;
reg [3:0] cpu_period2;                   // the period in half clocks
always @(*)
	case (cpu_slow_s2)
		3'd1: cpu_period2 = 4'd4;
		3'd2: cpu_period2 = 4'd5;
		3'd3: cpu_period2 = 4'd6;
		3'd4: cpu_period2 = 4'd7;
		3'd5: cpu_period2 = 4'd8;
		3'd6: cpu_period2 = 4'd10;
		default: cpu_period2 = 4'd12;
	endcase
always @(posedge cpuclk_p) begin
	cpu_slow_s1 <= system_cpu_slow;
	cpu_slow_s2 <= cpu_slow_s1;
	if (cpu_acc + 4'd2 >= cpu_period2) begin
		cpu_acc <= cpu_acc + 4'd2 - cpu_period2;
		cpu_clk_ena <= 1'b1;
	end
	else begin
		cpu_acc <= cpu_acc + 4'd2;
		cpu_clk_ena <= 1'b0;
	end
end

cpu_wb cpu1(
	.clk_ppu_p    (cpuclk_p),
	.clk_ppu_n    (cpuclk_n),
	.clk50hz      (vsync),

	.addr_ram     (addr_cpu_o),
	.duot_ram     (data_cpu_o),
	.dinp_ram     (data_cpu_i),
	.mask_ram     (mask_cpu_o),
	.read_ram     (read_cpu_o),
	.wrte_ram     (wrte_cpu_o),
	.askn_ram     (askn_cpu_i),

	.pin_vm_init_o(cpu_vm_init_o),
	.pin_vm_dclo_i(cpu_dclo_s[1]),
	.pin_vm_aclo_i(cpu_aclo_s[1]),
	.pin_vm_halt_i(cpu_halt_s[1]),

	.pin_vm_virq_i(cpu_vm_virq_i),

	.pin_wbm_adr_o(cpu_wbm_adr_o),
	.pin_wbm_dat_o(cpu_wbm_dat_o),
	.pin_wbm_dat_i(cpu_wbm_dat_i),
	.pin_wbm_cyc_o(cpu_wbm_cyc_o),
	.pin_wbm_wre_o(cpu_wbm_wre_o),
	.pin_wbm_sel_o(cpu_wbm_sel_o),
	.pin_wbm_stb_o(cpu_wbm_stb_o),
	.pin_wbm_ack_i(cpu_wbm_ack_i),
	.pin_wbi_dat_i(cpu_wbi_dat_i),
	.pin_wbi_ack_i(cpu_wbi_ack_i),
	.pin_wbi_stb_o(cpu_wbi_stb_o),

	.pin_tmr_ena_i(pin_tmr_ena_o),
	.pin_clk_slow_i(cpu_slow),
	.pin_clk_ena_i(cpu_clk_ena)
);

//------------------------------------------------------------//
wire cpu_wbi_stb_o_vp1;   // the CPU's interrupt-ack chain, on to vp65
wire [7:0] lpt_data;      // port A of the printer port, 0177100 - the older Covox's byte

vp1_120 vp1(
	.clk          (clk_25),

	.cpu_vm_init_i(cpu_vm_init_o),
	.cpu_vm_virq_o(cpu_vm_virq_i_vp),

	.cpu_wbm_adr_i(cpu_wbm_adr_o),
	.cpu_wbm_dat_i(cpu_wbm_dat_o),
	.cpu_wbm_dat_o(cpu_wbm_dat_i_vp),
	.cpu_wbm_cyc_i(cpu_wbm_cyc_o),
	.cpu_wbm_wre_i(cpu_wbm_wre_o),
	.cpu_wbm_sel_i(cpu_wbm_sel_o),
	.cpu_wbm_stb_i(cpu_wbm_stb_o),
	.cpu_wbm_ack_o(cpu_wbm_ack_i_vp),
	.cpu_wbi_dat_o(cpu_wbi_dat_i_vp),
	.cpu_wbi_ack_o(cpu_wbi_ack_i_vp),
	.cpu_wbi_stb_i(cpu_wbi_stb_o),

	.cpu_wbi_stb_o(cpu_wbi_stb_o_vp1),

	.ppu_vm_init_i(ppu_vm_init_o),
	.ppu_vm_virq_o(ppu_vm_virq_i_vp),

	.ppu_wbm_adr_i(ppu_wbm_adr_o),
	.ppu_wbm_dat_i(ppu_wbm_dat_o),
	.ppu_wbm_dat_o(ppu_wbm_dat_i_vp),
	.ppu_wbm_cyc_i(ppu_wbm_cyc_o),
	.ppu_wbm_wre_i(ppu_wbm_wre_o),
	.ppu_wbm_sel_i(ppu_wbm_sel_o),
	.ppu_wbm_stb_i(ppu_wbm_stb_o),
	.ppu_wbm_ack_o(ppu_wbm_ack_i_vp),
	.ppu_wbi_dat_o(ppu_wbi_dat_i_vp),
	.ppu_wbi_ack_o(ppu_wbi_ack_i_vp),
	.ppu_wbi_stb_i(ppu_wbi_stb_o_xm2),

	.ppu_wbi_stb_o(),

	.lpt_data     (lpt_data)
);

// The UKNC's own C2 serial port.
vp065 dd2(
	.pin_50MHz_clk(clk_50),
	.pin_vm_clk_p (cpuclk_n),

	.pin_vm_init_i(cpu_vm_init_o),
	.pin_vm_virq_o(vp65_vm_virq_i),

	.pin_wbm_adr_i(cpu_wbm_adr_o),
	.pin_wbm_dat_i(cpu_wbm_dat_o),
	.pin_wbm_dat_o(vp65_wbm_dat_i),
	.pin_wbm_wre_i(cpu_wbm_wre_o),
	.pin_wbm_stb_i(cpu_wbm_stb_o),
	.pin_wbm_ack_o(vp65_wbm_ack_i),
	.pin_wbi_dat_o(vp65_wbi_dat_i),
	.pin_wbi_ack_o(vp65_wbi_ack_i),
	.pin_wbi_stb_i(cpu_wbi_stb_o_vp1),

	.pin_wbi_stb_o(),

	.pin_tx_o     (uart_tx),
	.pin_rx_i     (uart_rx),
	.pin_ac_o     ()
);

//------------------------------------------------------------//
// The mixer (tang mixer.v): the Aberrant resistor network, low-pass, volume. The second Covox hangs on port A
// of the printer port (0177100) when Covox says Port 177100 or Both.
reg [7:0] lpt_sample = 8'd0;
always @(posedge ppuclk_p)
	lpt_sample <= system_covox[1] ? lpt_data : 8'd0;

mixer mix1(
	.clk      (ppuclk_p),
	.ay_a     (ay_a_channel),
	.ay_b     (ay_b_channel),
	.ay_c     (ay_c_channel),
	.beep     (sound & system_beeper),
	.covox    (covox_sample),
	.lpt      (lpt_sample),
	.stereo   (system_stereo),
	.lowpass  (system_lowpass),
	.oldfreaks(system_oldfreaks),
	.volume   (system_volume),
	.out_l    (audio_l),
	.out_r    (audio_r)
);

// The I2S DAC: one word a channel every 32 PPU clocks (97.9 kHz).
audio_drive ad1(
	.clk_1p536m(ppuclk_p),
	.rst_n     (init),

	.idata     (audio_l),
	.idata_rgt (audio_r),
	.req       (),

	.HP_BCK    (i2s_bck),
	.HP_WS     (i2s_ws),
	.HP_DIN    (i2s_din)
);

endmodule
