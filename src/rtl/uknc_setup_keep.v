`timescale 1ns / 1ps
`default_nettype none
/*
 Keeps the colors of the SETUP menu of the PPU (F7, "УСТАНОВКА РЕЖИМОВ": 3 symbol, 4 cell, 5 screen, 6 cursor)
 over resets and power off, in the EEPROM of the core: the DS1307 registers 14..20 of kg_mcu (rtc_mode 1), which
 the firmware keeps in /config/uknc.eep (core.json eeprom_bank 4..254). The real machine has no such memory.
 Not 12 and 13: kg_mcu_rtc does not send a write of 0C / 0D to the firmware (the flags of MC146818).

 The PPU ROM (src/roms/uknc_rom.hex, addresses of the PPU):
 - the menu keeps the items in PPU RAM 7154..7174, one word each: 7160 symbol, 7162 cell, 7164 screen, 7166
   cursor, a color 0..7 (bits B 1, G 2, R 4: green on black = 2, 0, 0). At its start the PPU copies them from
   the ROM table 100012 (count, then the words of 7152..7174; the colors at 100022..100030 = 7, 1, 1, 7);
 - the colors on the screen are those of the terminal contexts 22656 (the main one, the start screen; the ROM
   template 112142, count, then the words from offset 0 at 112144) and 22754 (template 112252, from 112254): symbol
   34 / 36 (the color and the one before), cell 40 / 42 and screen 44 / 46 (the color repeated in the 4 nibbles,
   the table 113512), cursor 70, and the word after the template (112242, 112350) goes to the cursor color byte
   @64. The templates 112040 and 112360 are the service lines (colors 6 on 0) and stay;
 - the menu writes an item with MOV R2,@4(R3) and DEC @4(R3) (101404, 101410), R3 = the descriptor of the
   submenu in ROM, whose word 4 is the address of the item: 101726 (7160), 101754 (7162), 102002 (7164),
   102030 (7166). The ESC color sequences of programs write the same cells by MOV R0,@#7160 etc. (117014..)
   and are not kept.
 So: a write of the PPU to one of the 4 cells within 4 bus cycles after the read of the descriptor word with
 its address is a choice in the menu; those 4 colors go into the ROM words above when the PPU reads them (at
 every start of the PPU, also after the OSD Reset) and into the EEPROM.

 The start test of the PPU (160410..160462) sums the 4 blocks of the ROM and compares with the table 176770; all
 the words above are in block 1 (100000..117777), so it has to see the real ones: the fetch of 160426 (the start
 of a block) turns the replacement off, the fetch of 160462 (RTS, also prefetched after every block but then
 160426 comes again before the data) turns it on.

 EEPROM layout (DS1307 registers): 14 'U' (55), 15 'K' (4B), 16 symbol, 17 cell, 18 screen, 19 cursor, 20 check
 = A5 xor (the sum of 14..19). Kept only when the magic, the colors (0..7) and the check are right: an empty
 (FF) or foreign EEPROM gives the colors of the ROM.

 Host side (clk, the kg_mcu clock): while the mcu is busy (the start of the core, the PPU held in reset) the
 registers are read again and again (the mcu sets them then); when busy drops they are checked. A choice in
 the menu is written 2.6 ms after the last change, twice (a strobe of the reply queue can be lost when
 another source asks in the same clock); the firmware saves the file 2 s after the last change.
 rtc_own: this drives rtc_a (else uknc_rtc_seed, which reads only right after busy drops).
*/

module uknc_setup_keep #(
	parameter [7:0] REG_FIRST = 8'd14    // the first of the 7 registers, see above
) (
	// the PPU (its clock, rising edge as ppu.v)
	input wire ppu_clk,
	input wire [15:0] ppu_adr,
	input wire ppu_we,
	input wire ppu_stb,
	input wire [1:0] ppu_sel,
	input wire [15:0] ppu_dat,
	input wire ppu_rom,              // the cycle reads the firmware ROM (ppu.v rom)
	output reg rom_ovr,
	output reg [15:0] rom_ovr_dat,

	// the host (kg_mcu)
	input wire clk,
	input wire busy,
	output reg rtc_own = 1'b1,
	output reg [7:0] rtc_a = REG_FIRST,
	output reg [7:0] rtc_di = 8'd0,
	output reg rtc_wr = 1'b0,
	input wire [7:0] rtc_do
);

localparam [11:0] ROM_COLORS = {3'd7, 3'd1, 3'd1, 3'd7}; // cursor, screen, cell, symbol
localparam [7:0] REG_LAST = REG_FIRST + 8'd6;

//---------------- PPU side ----------------
reg [2:0] c_sym = 3'd7, c_cell = 3'd1, c_scr = 3'd1, c_cur = 3'd7;
reg [3:0] armed = 4'd0;              // the descriptor word of item n was read
reg [1:0] armed_n [0:3];             // bus cycles since
reg stb_d = 1'b0;
reg [1:0] busy_s = 2'b11;
reg chg_tgl = 1'b0;
wire [11:0] ld_colors;               // host side, stable while busy_s is low

function [15:0] nib4;
	input [2:0] c;
	nib4 = {4{1'b0, c}};
endfunction

// the ROM words with the colors (word addresses of the PPU), not for the sum of the start test
reg ovr_on = 1'b1;
always @(*) begin
	rom_ovr = ppu_rom & ~ppu_we & ovr_on;
	case ({ppu_adr[15:1], 1'b0})
		16'o100022: rom_ovr_dat = {13'd0, c_sym};
		16'o100024: rom_ovr_dat = {13'd0, c_cell};
		16'o100026: rom_ovr_dat = {13'd0, c_scr};
		16'o100030: rom_ovr_dat = {13'd0, c_cur};
		16'o112200, 16'o112202, 16'o112310, 16'o112312: rom_ovr_dat = {13'd0, c_sym};
		16'o112204, 16'o112206, 16'o112314, 16'o112316: rom_ovr_dat = nib4(c_cell);
		16'o112210, 16'o112212, 16'o112320, 16'o112322: rom_ovr_dat = nib4(c_scr);
		16'o112234, 16'o112242, 16'o112344, 16'o112350: rom_ovr_dat = {13'd0, c_cur};
		default: begin rom_ovr = 1'b0; rom_ovr_dat = 16'd0; end
	endcase
end

// item n: the descriptor word with its address, the cell
function [15:0] desc_adr;
	input [1:0] n;
	case (n)
		2'd0: desc_adr = 16'o101726;
		2'd1: desc_adr = 16'o101754;
		2'd2: desc_adr = 16'o102002;
		default: desc_adr = 16'o102030;
	endcase
endfunction

function [15:0] cell_adr;
	input [1:0] n;
	cell_adr = 16'o7160 + {13'd0, n, 1'b0};
endfunction

integer i;
always @(posedge ppu_clk) begin
	busy_s <= {busy_s[0], busy};
	stb_d <= ppu_stb;
	if (ppu_stb && ppu_rom && !ppu_we) begin
		if ({ppu_adr[15:1], 1'b0} == 16'o160426) ovr_on <= 1'b0;
		else if ({ppu_adr[15:1], 1'b0} == 16'o160462) ovr_on <= 1'b1;
	end
	if (busy_s[1]) begin
		{c_cur, c_scr, c_cell, c_sym} <= ld_colors;
		armed <= 4'd0;
		ovr_on <= 1'b1;
	end
	else begin
		for (i = 0; i < 4; i = i + 1) begin
			if (ppu_stb && !stb_d) begin
				// a new bus cycle: a write of the menu, the cycles of an armed item
				if (ppu_we && armed[i] && ppu_sel == 2'b11 && {ppu_adr[15:1], 1'b0} == cell_adr(i)) begin
					case (i)
						0: c_sym <= ppu_dat[2:0];
						1: c_cell <= ppu_dat[2:0];
						2: c_scr <= ppu_dat[2:0];
						default: c_cur <= ppu_dat[2:0];
					endcase
					chg_tgl <= ~chg_tgl;
				end
				armed_n[i] <= armed_n[i] + 2'd1;
				if (armed_n[i] == 2'd3) armed[i] <= 1'b0;
			end
			else if (ppu_stb && ppu_rom && !ppu_we && ppu_adr == desc_adr(i)) begin
				armed[i] <= 1'b1;
				armed_n[i] <= 2'd0;
			end
		end
	end
end

//---------------- host side ----------------
reg [7:0] r [0:6];                   // the 7 registers as read while busy
reg [11:0] ld = ROM_COLORS;
assign ld_colors = ld;
reg busy_d = 1'b1;
reg [1:0] rd = 2'd0;
reg [2:0] chg_s = 3'd0;
reg pend = 1'b0;
reg [1:0] pass = 2'd0;               // write passes left
reg [16:0] quiet = 17'd0;
reg writing = 1'b0;
reg [2:0] wi = 3'd0;
reg [2:0] wgap = 3'd0;
reg [7:0] w [0:6];

wire [7:0] sum_r = r[0] + r[1] + r[2] + r[3] + r[4] + r[5];
wire ok_r = r[0] == 8'h55 && r[1] == 8'h4B && r[2][7:3] == 5'd0 && r[3][7:3] == 5'd0 && r[4][7:3] == 5'd0 &&
	r[5][7:3] == 5'd0 && r[6] == (8'hA5 ^ sum_r);

// the colors as seen by the PPU side: stable once pend has been quiet for 2.6 ms
wire [7:0] w2 = {5'd0, c_sym}, w3 = {5'd0, c_cell}, w4 = {5'd0, c_scr}, w5 = {5'd0, c_cur};
wire [7:0] sum_w = 8'h55 + 8'h4B + w2 + w3 + w4 + w5;

always @(posedge clk) begin
	busy_d <= busy;
	chg_s <= {chg_s[1:0], chg_tgl};
	rtc_wr <= 1'b0;
	if (busy) begin
		// read the 7 round robin: address, a clock, data
		rtc_own <= 1'b1;
		writing <= 1'b0;
		pend <= 1'b0;
		pass <= 2'd0;
		rd <= rd + 2'd1;
		if (rtc_a < REG_FIRST || rtc_a > REG_LAST) begin
			rtc_a <= REG_FIRST;
			rd <= 2'd0;
		end
		else if (rd == 2'd2) begin
			rd <= 2'd0;
			r[rtc_a - REG_FIRST] <= rtc_do;
			rtc_a <= rtc_a == REG_LAST ? REG_FIRST : rtc_a + 8'd1;
		end
	end
	else begin
		if (busy_d) begin
			ld <= ok_r ? {r[5][2:0], r[4][2:0], r[3][2:0], r[2][2:0]} : ROM_COLORS;
			rtc_own <= 1'b0;
			rtc_a <= REG_FIRST;
			rd <= 2'd0;
		end
		if (chg_s[2] != chg_s[1]) begin
			pend <= 1'b1;
			pass <= 2'd2;
			quiet <= 17'd0;
		end
		else if (writing) begin
			wgap <= wgap + 3'd1;
			if (wgap == 3'd0) begin
				rtc_a <= REG_FIRST + {5'd0, wi};
				rtc_di <= w[wi];
			end
			else if (wgap == 3'd1)
				rtc_wr <= 1'b1;
			else if (wgap == 3'd7) begin
				wi <= wi + 3'd1;
				if (wi == 3'd6) begin
					writing <= 1'b0;
					rtc_own <= 1'b0;
					quiet <= 17'd0;
				end
			end
		end
		else if (pend) begin
			quiet <= quiet + 17'd1;
			if (quiet[16]) begin
				w[0] <= 8'h55; w[1] <= 8'h4B; w[2] <= w2; w[3] <= w3; w[4] <= w4; w[5] <= w5;
				w[6] <= 8'hA5 ^ sum_w;
				writing <= 1'b1;
				rtc_own <= 1'b1;
				wi <= 3'd0;
				wgap <= 3'd0;
				pass <= pass - 2'd1;
				if (pass == 2'd1) pend <= 1'b0;
			end
		end
	end
end

endmodule
