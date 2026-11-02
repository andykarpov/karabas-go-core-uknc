`timescale 1ns / 1ps
`default_nettype none
/*
 The geometry of the HDD image (slot 4) from its sector 0, read by the core itself when the image is mounted.
 In karabas-forge the firmware overlay read it (mc0511_geometry, mc0511_parse_geometry of mc0511_media.h, after
 Hard.cpp of UKNCBTL / sdc.c of tang) and sent it as CMD_SWITCHES 240-244; here it needs no firmware.

 - a WD home block: words 0-2 = 54A9 FFEF FEFF (plain) or their complement AB56 0010 0100 (inverted):
   SPT = word 4, heads = word 5 / SPT (complemented first when inverted);
 - else ID / plain: bytes 0x1F0-0x1FB all FF = inverted; SPT = byte 0, heads = byte 1 (complemented when inverted);
 - cylinders = size / 512 / SPT / heads, at most 65535 (0 when SPT or heads is 0).

 The read goes through the cartridge side of sd_arbiter (probe_rd / probe_active in place of the IDE requests);
 valid is 0 from the mount until the geometry is ready, the IDE is not present meanwhile (ide.v takes SPT / heads
 while it is not present).
*/

module uknc_hdd_geometry (
	input wire clk,
	input wire mounted,          // pulse: slot 4 got an image of this size (0 = none)
	input wire [31:0] size,

	output wire probe_active,
	output reg probe_rd = 1'b0,
	input wire owner,            // sd_arbiter: the cartridge side owns the sector path
	input wire sd_busy,
	input wire sd_done,
	input wire outen,            // a byte of the sector (cartridge side)
	input wire [8:0] addr,
	input wire [7:0] data,

	output reg valid = 1'b0,
	output reg [7:0] spt = 8'd0,
	output reg [7:0] heads = 8'd0,
	output reg inv = 1'b0,
	output reg [15:0] cyl = 16'd0
);

localparam S_IDLE = 3'd0, S_REQ = 3'd1, S_WAIT = 3'd2, S_PARSE = 3'd3, S_DIV_HEADS = 3'd4, S_MUL = 3'd5,
           S_DIV_CYL = 3'd6;
reg [2:0] st = S_IDLE;
assign probe_active = st == S_REQ || st == S_WAIT;

reg [31:0] sectors = 32'd0;
reg [7:0] b [0:11];
reg [7:0] tail_and = 8'hFF;

// sequential divider: quotient q = n / d (restoring, one bit a clock)
reg [31:0] n = 32'd0, q = 32'd0;
reg [32:0] r = 33'd0;
reg [15:0] d = 16'd0;
reg [5:0] bits = 6'd0;
wire [32:0] r_shift = {r[31:0], n[31]};
wire [32:0] r_sub = r_shift - {17'd0, d};

wire [15:0] w0 = {b[1], b[0]}, w1 = {b[3], b[2]}, w2 = {b[5], b[4]};
wire home_plain = w0 == 16'h54A9 && w1 == 16'hFFEF && w2 == 16'hFEFF;
wire home_inv = w0 == 16'hAB56 && w1 == 16'h0010 && w2 == 16'h0100;

integer i;
always @(posedge clk) begin
	if (mounted) begin
		valid <= 1'b0;
		spt <= 8'd0;
		heads <= 8'd0;
		inv <= 1'b0;
		cyl <= 16'd0;
		sectors <= size >> 9;
		probe_rd <= |size;
		tail_and <= 8'hFF;
		st <= |size ? S_REQ : S_IDLE;
	end
	else case (st)
		S_REQ:
			// img_sdc takes the request with sd_busy: drop it then
			if (owner && sd_busy) begin
				probe_rd <= 1'b0;
				st <= S_WAIT;
			end
		S_WAIT: begin
			if (outen) begin
				if (addr < 9'd12) b[addr[3:0]] <= data;
				if (addr >= 9'h1F0 && addr <= 9'h1FB) tail_and <= tail_and & data;
			end
			if (sd_done) st <= S_PARSE;
		end
		S_PARSE:
			if (home_plain || home_inv) begin
				inv <= home_inv;
				spt <= home_inv ? ~b[8] : b[8];
				// heads = word 5 / SPT
				n <= {home_inv ? ~{b[11], b[10]} : {b[11], b[10]}, 16'd0};
				d <= {8'd0, home_inv ? ~b[8] : b[8]};
				r <= 33'd0;
				q <= 32'd0;
				bits <= 6'd16;
				st <= (home_inv ? ~b[8] : b[8]) == 8'd0 ? S_MUL : S_DIV_HEADS;
			end
			else begin
				inv <= tail_and == 8'hFF;
				spt <= tail_and == 8'hFF ? ~b[0] : b[0];
				heads <= tail_and == 8'hFF ? ~b[1] : b[1];
				st <= S_MUL;
			end
		S_DIV_HEADS:
			if (bits != 6'd0) begin
				bits <= bits - 6'd1;
				n <= {n[30:0], 1'b0};
				if (!r_sub[32]) begin r <= r_sub; q <= {q[30:0], 1'b1}; end
				else begin r <= r_shift; q <= {q[30:0], 1'b0}; end
			end
			else begin
				heads <= q[7:0];
				st <= S_MUL;
			end
		S_MUL: begin
			// cylinders = sectors / (SPT * heads)
			n <= sectors;
			d <= spt * heads;
			r <= 33'd0;
			q <= 32'd0;
			bits <= 6'd32;
			if (spt == 8'd0 || heads == 8'd0) begin
				cyl <= 16'd0;
				valid <= 1'b1;
				st <= S_IDLE;
			end
			else
				st <= S_DIV_CYL;
		end
		S_DIV_CYL:
			if (bits != 6'd0) begin
				bits <= bits - 6'd1;
				n <= {n[30:0], 1'b0};
				if (!r_sub[32]) begin r <= r_sub; q <= {q[30:0], 1'b1}; end
				else begin r <= r_shift; q <= {q[30:0], 1'b0}; end
			end
			else begin
				cyl <= |q[31:16] ? 16'hFFFF : q[15:0];
				valid <= 1'b1;
				st <= S_IDLE;
			end
		default: ;
	endcase
end

endmodule
