`timescale 1ns / 1ps
`default_nettype none
/*
 Sets the Kakave clock from the clock of the board once the core has started. The firmware sends the time at the
 start of the core (rtc_mode 1: DS1307 registers in BCD, 0 seconds, 1 minutes, 2 hours, 4 date, 5 month, 6 year)
 into the RTC RAM of kg_mcu while it is busy; when busy drops, this reads the registers and sends the fields to
 kakave.v (set_tgl / set_field / set_val: 0 year-2020, 1 month-1, 2 date-1, 3 hours, 4 minutes, 5 seconds, the
 seconds last since the minutes clear them). Years before 2020 are not sent (the clock keeps its own time).
 In karabas-forge the firmware overlay did this through OSD items and CMD_SWITCHES 245 (mc0511_rtc_seed).
*/

module uknc_rtc_seed (
	input wire clk,
	input wire busy,             // kg_mcu BUSY
	output reg [7:0] rtc_a = 8'd0,
	input wire [7:0] rtc_do,     // a clock after rtc_a
	output reg set_tgl = 1'b0,
	output reg [2:0] set_field = 3'd0,
	output reg [7:0] set_val = 8'd0
);

function [7:0] bcd;
	input [7:0] v;
	bcd = v[7:4] * 8'd10 + v[3:0];
endfunction

reg busy_d = 1'b1;
reg run = 1'b0;
reg [2:0] idx = 3'd0;           // the register being read: 0..6
reg [1:0] rd = 2'd0;
reg [7:0] t [0:6];
reg sending = 1'b0;
reg [2:0] field = 3'd0;
reg [7:0] gap = 8'd0;           // 256 clocks between fields: kakave takes the toggle through 2 flip-flops of the PPU clock

always @(posedge clk) begin
	busy_d <= busy;
	if (busy) begin
		run <= 1'b0;
		sending <= 1'b0;
	end
	else if (busy_d) begin
		run <= 1'b1;
		idx <= 3'd0;
		rd <= 2'd0;
		rtc_a <= 8'd0;
	end
	else if (run) begin
		// read register idx: address, one clock, data
		rd <= rd + 2'd1;
		if (rd == 2'd2) begin
			t[idx] <= rtc_do;
			rd <= 2'd0;
			if (idx == 3'd6) begin
				run <= 1'b0;
				sending <= 1'b1;
				field <= 3'd0;
				gap <= 8'd0;
			end
			else begin
				idx <= idx + 3'd1;
				rtc_a <= {5'd0, idx + 3'd1};
			end
		end
	end
	else if (sending) begin
		gap <= gap + 8'd1;
		if (gap == 8'd0) begin
			if (bcd(t[6]) < 8'd20)
				sending <= 1'b0;
			else begin
				set_field <= field;
				case (field)
					3'd0: set_val <= bcd(t[6]) - 8'd20;
					3'd1: set_val <= bcd(t[5]) - 8'd1;
					3'd2: set_val <= bcd(t[4]) - 8'd1;
					3'd3: set_val <= bcd(t[2] & 8'h3F);
					3'd4: set_val <= bcd(t[1]);
					default: set_val <= bcd(t[0] & 8'h7F);
				endcase
			end
		end
		else if (gap == 8'd8 && sending) begin
			set_tgl <= ~set_tgl;
			if (field == 3'd5) sending <= 1'b0;
			field <= field + 3'd1;
		end
	end
end

endmodule
