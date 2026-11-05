// The OSD switches of core.json, the same order on every board: register n = softsw[n*8 +: 8]
// (CMD_SWITCHES index = the position of the item in the flat "osd" list, file items included).
//  0 F FDD0 (slot 0)           1 F HDD0 (slot 4)       2 Kakave mouse      3 RTC controller   4 Color RGB / BGR
//  5 T Reset (F12)             6 Volume                7 Beeper            8 Covox            9-11 AY1-AY3
// 12 Stereo                   13 Low-pass             14 Old freaks       15 FDD controller  16 FDD0 write prot
// 17 F FDD1 (slot 1)          18 FDD1 write prot      19 F FDD2 (slot 2)  20 FDD2 write prot 21 F FDD3 (slot 3)
// 22 FDD3 write prot          23 Physical FDD         24 HDD controller   25 HDD write prot  26 Image format
// 27 HDD delay (x 50 us)      then the page entries (M) and the About text (P)
`define UKNC_SW_N 28
`define UKNC_SW_INIT 224'h0f000000000000000000000001000101010101000101000000000000
