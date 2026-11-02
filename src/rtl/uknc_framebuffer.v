`timescale 1ns / 1ps
`default_nettype none
/*
 The frame buffer of the UKNC video in the SRAM of the board, with a standard 800 x 600 @ 60 Hz output.

 The raster of sdram2 (tang) is not a standard mode: 640 x 600 of 800 x 618 at a 25 MHz pixel (each pixel two
 clocks of clkram), 31.25 kHz, 50.57 Hz. Monitors and HDMI capture devices do not take it, so it is written into
 the SRAM (the UKNC does not use it) and read out in the VESA mode 800 x 600 @ 60 Hz, 40 MHz pixel (1056 x 628,
 positive syncs), the picture 640 x 600 in its middle (80 pixels of border each side). One buffer: the frame rates
 differ (50.57 / 60 Hz), a moving picture can show a seam where the two frames meet.

 - capture (clkram): a pixel is 6 bits (2 per channel: the levels 0, 100, 110, 111 of the 3-bit colours of
   sdram2), two pixels a 16-bit word, the word goes into a write FIFO with its address {row, x / 2}. sdram2 shows
   every line of the UKNC (288) twice: only the even lines of its 600 are written (300 rows), the output shows
   each row twice (this halves the SRAM traffic);
 - SRAM (clkram, IS61WV20488 10 ns): a write takes two clocks, the address and data out on the first edge, WE low
   from the middle of the first clock to the second edge (ODDR2: 10 ns pulse, 10 ns address setup, 20 ns hold);
   a read takes two clocks (the address on an edge, the data into the IOB register two edges later: pad out +
   tAA + pad in is ~21 ns);
   one idle clock between reading (SRAM drives) and writing (FPGA drives);
 - read-out (clk_vid): two row buffers in a block RAM; at the start of the even output line 2k the row k + 1 is
   fetched into the other buffer (a toggle to clkram with the row), in chunks of 32 reads between the writes.
*/

module uknc_framebuffer (
	input wire clkram,

	// source raster (clkram): the colours of sdram2 and its syncs / visible
	input wire [2:0] red,
	input wire [2:0] green,
	input wire [2:0] blue,
	input wire vsync,
	input wire visible,

	// SRAM
	output reg [20:0] sram_a = 21'd0,
	inout wire [15:0] sram_d,
	output wire [1:0] sram_we_n,
	output wire [1:0] sram_oe_n,

	// output (clk_vid, 40 MHz)
	input wire clk_vid,
	output reg [23:0] rgb = 24'd0,
	output reg hs = 1'b0,
	output reg vs = 1'b0,
	output reg de = 1'b0
);

//---------------------------------------------------------------- capture
function [1:0] level;
	input [2:0] v;
	level = v[2] ? (v[1] ? (v[0] ? 2'd3 : 2'd2) : 2'd1) : 2'd0;
endfunction

wire [5:0] px = {level(red), level(green), level(blue)};

reg vis_d = 1'b0;
reg ph = 1'b0, half = 1'b0;
reg [9:0] sy = 10'd0;
reg [8:0] wx = 9'd0;
reg [5:0] p0 = 6'd0;

// write FIFO: {address 19, data 12}
reg [30:0] wf [0:63];
reg [5:0] wf_wp = 6'd0, wf_rp = 6'd0;
wire [5:0] wf_count = wf_wp - wf_rp;
wire wf_empty = wf_wp == wf_rp;
reg wf_push = 1'b0;
reg [30:0] wf_in = 31'd0;
reg wf_pop;

always @(posedge clkram) begin
	vis_d <= visible;
	wf_push <= 1'b0;
	if (vsync) sy <= 10'd0;
	else if (vis_d && !visible && sy != 10'd1023) sy <= sy + 10'd1;
	if (!visible) begin
		ph <= 1'b0;
		half <= 1'b0;
		wx <= 9'd0;
	end
	else begin
		ph <= ~ph;
		if (ph) begin              // the second clock of a pixel
			half <= ~half;
			if (!half) p0 <= px;
			else begin
				if (sy < 10'd600 && !sy[0] && wx < 9'd320) begin
					wf_in <= {1'b0, sy[9:1], wx, px, p0};
					wf_push <= 1'b1;
				end
				wx <= wx + 9'd1;
			end
		end
	end
	if (wf_push && wf_count != 6'd63) begin
		wf[wf_wp] <= wf_in;
		wf_wp <= wf_wp + 6'd1;
	end
	if (wf_pop) wf_rp <= wf_rp + 6'd1;
end
wire [30:0] wf_out = wf[wf_rp];

//---------------------------------------------------------------- read requests from the output side
reg req_tgl_v = 1'b0;           // clk_vid
reg [9:0] req_row_v = 10'd0;
reg [2:0] req_s = 3'd0;         // clkram
reg rd_pending = 1'b0;
reg [9:0] rd_row = 10'd0;
reg [8:0] rd_cnt = 9'd0;

//---------------------------------------------------------------- SRAM controller
localparam S_IDLE = 2'd0, S_W1 = 2'd1, S_RD = 2'd2;
reg [1:0] st = S_IDLE;
reg drive = 1'b0;               // the FPGA drives the data bus
reg oe_on = 1'b0;               // the SRAM drives the data bus (OE low)
reg we_c0 = 1'b0;               // the first clock of a write
reg [15:0] dout = 16'd0;
(* IOB = "TRUE" *) reg [15:0] din = 16'd0;
reg [4:0] chunk = 5'd0;
reg issued = 1'b0, iss1 = 1'b0, iss2 = 1'b0;
reg [9:0] lb_a = 10'd0, lb_a1 = 10'd0, lb_a2 = 10'd0;
reg rd_ph = 1'b0;

assign sram_d = drive ? dout : 16'hzzzz;
assign sram_oe_n = {2{~oe_on}};

// WE: high on the rising edge, low from the falling edge of the first clock of a write
// (one ODDR2 for each pad: it sits in the IOB of its pad)
ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b1), .SRTYPE("SYNC")) we_oddr0(
	.Q(sram_we_n[0]), .C0(clkram), .C1(~clkram), .CE(1'b1), .D0(1'b1), .D1(~we_c0), .R(1'b0), .S(1'b0));
ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b1), .SRTYPE("SYNC")) we_oddr1(
	.Q(sram_we_n[1]), .C0(clkram), .C1(~clkram), .CE(1'b1), .D0(1'b1), .D1(~we_c0), .R(1'b0), .S(1'b0));

// the line buffers: {bank, word}
reg [15:0] lb [0:1023];

always @(posedge clkram) begin
	req_s <= {req_s[1:0], req_tgl_v};
	if (req_s[2] != req_s[1]) begin
		rd_row <= req_row_v;     // stable for a whole line before the toggle
		rd_cnt <= 9'd0;
		rd_pending <= 1'b1;
	end

	we_c0 <= 1'b0;
	wf_pop <= 1'b0;
	issued <= 1'b0;

	// read data: the address on edge 0, the data into din on edge 2, into the row buffer on edge 3
	din <= sram_d;
	iss1 <= issued;
	iss2 <= iss1;
	lb_a1 <= lb_a;
	lb_a2 <= lb_a1;
	if (iss2) lb[lb_a2] <= din;

	case (st)
		S_IDLE:
			if (!wf_empty && !wf_pop) begin
				if (oe_on) oe_on <= 1'b0;   // the SRAM lets go of the bus first
				else begin
					sram_a <= {2'b00, wf_out[30:12]};
					dout <= {4'd0, wf_out[11:0]};
					drive <= 1'b1;
					we_c0 <= 1'b1;
					wf_pop <= 1'b1;
					st <= S_W1;
				end
			end
			else if (rd_pending) begin
				if (drive) drive <= 1'b0;   // the FPGA lets go of the bus first
				else if (!oe_on) oe_on <= 1'b1;
				else begin
					chunk <= 5'd0;
					rd_ph <= 1'b0;
					st <= S_RD;
				end
			end
		S_W1:
			st <= S_IDLE;                // address, data and drive held through this clock
		S_RD: begin
			rd_ph <= ~rd_ph;
			if (!rd_ph) begin
				if (rd_cnt == 9'd320) begin
					rd_pending <= 1'b0;
					st <= S_IDLE;
				end
				else begin
					sram_a <= {2'b00, rd_row, rd_cnt};
					issued <= 1'b1;
					lb_a <= {rd_row[0], rd_cnt};
					rd_cnt <= rd_cnt + 9'd1;
					chunk <= chunk + 5'd1;
				end
			end
			else if (chunk == 5'd0) st <= S_IDLE;    // 32 reads done (the count wrapped)
		end
		default: st <= S_IDLE;
	endcase
end

//---------------------------------------------------------------- output 800 x 600 @ 60 Hz
reg [10:0] hc = 11'd0;
reg [9:0] vc = 10'd0;
reg [15:0] lb_q = 16'd0;
reg act1 = 1'b0, sel1 = 1'b0, act2 = 1'b0, sel2 = 1'b0;
reg [1:0] hs_d = 2'b00, vs_d = 2'b00, de_d = 2'b00;

wire [10:0] sx = hc - 11'd80;   // the source pixel
wire in_pic = hc >= 11'd80 && hc < 11'd720 && vc < 10'd600;
// at the start of the even line 2k: the row k + 1 (at line 626: the row 0 of the next frame)
wire [9:0] next_row = (vc == 10'd626) ? 10'd0 : {1'b0, vc[9:1]} + 10'd1;

function [7:0] expand;
	input [1:0] c;
	expand = c == 2'd3 ? 8'hFF : c == 2'd2 ? 8'hDB : c == 2'd1 ? 8'h92 : 8'h00;
endfunction

always @(posedge clk_vid) begin
	if (hc == 11'd1055) begin
		hc <= 11'd0;
		vc <= (vc == 10'd627) ? 10'd0 : vc + 10'd1;
	end
	else
		hc <= hc + 11'd1;

	// fetch the next row at the start of an even line
	if (hc == 11'd0 && !vc[0] && next_row < 10'd300) begin
		req_row_v <= next_row;
		req_tgl_v <= ~req_tgl_v;
	end

	// pipeline: address -> line buffer word -> colour
	lb_q <= lb[{vc[1], sx[9:1]}];   // the row vc / 2
	act1 <= in_pic;
	sel1 <= sx[0];
	act2 <= act1;
	if (act1) rgb <= sel1 ? {expand(lb_q[11:10]), expand(lb_q[9:8]), expand(lb_q[7:6])}
	                      : {expand(lb_q[5:4]), expand(lb_q[3:2]), expand(lb_q[1:0])};
	else rgb <= 24'd0;

	hs_d <= {hs_d[0], hc >= 11'd840 && hc < 11'd968};
	vs_d <= {vs_d[0], vc >= 10'd601 && vc < 10'd605};
	de_d <= {de_d[0], hc < 11'd800 && vc < 10'd600};
	hs <= hs_d[0];
	vs <= vs_d[0];
	de <= de_d[0];
end

endmodule
