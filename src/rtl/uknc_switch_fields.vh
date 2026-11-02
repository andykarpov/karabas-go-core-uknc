// the fields of the OSD switches (uknc_switches.vh), included after softsw
wire sw_mouse_en = softsw[2*8];
wire sw_rtc_en = softsw[3*8];
wire sw_bgr = softsw[4*8];
wire sw_reset = softsw[5*8];
wire [1:0] sw_volume = softsw[6*8 +: 2];
wire sw_beeper = softsw[7*8];
wire [1:0] sw_covox = softsw[8*8 +: 2];
wire [2:0] sw_ay_en = {softsw[11*8], softsw[10*8], softsw[9*8]};
wire sw_stereo = softsw[12*8];
wire sw_lowpass = softsw[13*8];
wire sw_oldfreaks = softsw[14*8];
wire sw_fdd_en = softsw[15*8];
wire [3:0] sw_floppy_wprot = {softsw[22*8], softsw[20*8], softsw[18*8], softsw[16*8]};
wire [2:0] sw_physical_fdd = (softsw[23*8 +: 8] <= 8'd4) ? softsw[23*8 +: 3] : 3'd0;
wire sw_hdd_en = softsw[24*8];
wire sw_hdd_wprot = softsw[25*8];
wire [1:0] sw_hdd_mode = softsw[26*8 +: 2];
wire [5:0] sw_hdd_delay = {softsw[27*8 +: 4], 1'b0}; // 0..750 us in steps of 50 (tang: 25 us per step)
