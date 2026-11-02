`timescale 1ns/1ps
// Fixed core video, 50 MHz pixel clock; the machine and OSD raster are unchanged.
// No FT812 clock switching is needed by the UKNC core.
module mc0511_hdmi(input wire clk, reset, input wire [23:0] rgb,
 input wire hs, vs, de, input wire [15:0] audio_l, audio_r,
 output wire [3:0] tmds_p, tmds_n);
wire clk0, feedback, serial_raw, serial_n_raw, serial, serial_n, locked;
DCM_SP #(.CLKDV_DIVIDE(2.0),.CLKFX_DIVIDE(1),.CLKFX_MULTIPLY(5),
 .CLKIN_DIVIDE_BY_2("FALSE"),.CLKIN_PERIOD(20.0),.CLKOUT_PHASE_SHIFT("NONE"),
 .CLK_FEEDBACK("1X"),.DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"),.PHASE_SHIFT(0),.STARTUP_WAIT("FALSE")) dcm(
 .CLKIN(clk),.CLKFB(feedback),.CLK0(clk0),.CLK90(),.CLK180(),.CLK270(),
 .CLK2X(),.CLK2X180(),.CLKFX(serial_raw),.CLKFX180(serial_n_raw),.CLKDV(),
 .PSCLK(1'b0),.PSEN(1'b0),.PSINCDEC(1'b0),.PSDONE(),.LOCKED(locked),
 .STATUS(),.RST(reset),.DSSEN(1'b0));
BUFG fb(.I(clk0),.O(feedback));
BUFG sc(.I(serial_raw),.O(serial));
BUFG sn(.I(serial_n_raw),.O(serial_n));
reg [2:0] reset_sync=3'b111;
always @(posedge clk or negedge locked)
 if(!locked) reset_sync<=3'b111; else reset_sync<={reset_sync[1:0],1'b0};
// Fractional accumulator: exactly 48000 samples per 50000000 pixel clocks.
// Capture signed mixer words at the pixel edge; transmit them as signed 24-bit PCM.
reg [25:0] phase=0;
reg sample=0;
reg [23:0] left=0,right=0;
always @(posedge clk) begin
 sample<=0;
 if(reset_sync[2]) phase<=0;
 else if(phase>=26'd49952000) begin
  phase<=phase-26'd49952000; sample<=1;
  left<={audio_l,8'd0}; right<={audio_r,8'd0};
 end else phase<=phase+26'd48000;
end
hdmi_tx #(.SAMPLE_FREQ(48000)) tx(.clk(clk),.sclk(serial),.sclk_n(serial_n),
 .reset(reset_sync[2]),.rgb(rgb),.hsync(hs),.vsync(vs),.de(de),
 .audio_en(1'b1),.audio_l(left),.audio_r(right),.audio_clk(sample),
 .tx_clk_p(tmds_p[3]),.tx_clk_n(tmds_n[3]),.tx_d_p(tmds_p[2:0]),.tx_d_n(tmds_n[2:0]));
endmodule
