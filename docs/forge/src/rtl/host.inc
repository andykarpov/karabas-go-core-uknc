// Karabas SPI and checked image-sector transport, all on the source's 25 MHz domain.
wire host_busy;
wire [1:0] host_buttons;
wire [15:0] softsw_command,osd_command;
wire [55:0] kb;
wire [7:0] mouse_rep_dx,mouse_rep_dy;
wire [2:0] mouse_buttons;
wire mouse_rep_tgl;
wire [5:0] mouse_q={mouse_buttons[1:0],4'b0000};
wire [7:0] keycode;
wire [7:0] img_mounted,img_data,img_result;
wire [63:0] img_size;
wire img_data_wr,img_result_wr,img_q_wr,img_q_ack;
wire [8:0] img_data_addr;
wire [15:0] img_sum;
wire [23:0] img_q_di;
kg_mcu #(.ENABLE_RTC(0),.ENABLE_UART(0),.ENABLE_MATRIX(1),.ENABLE_IMG(1),
 .ENABLE_FILE(0),.ENABLE_FT(0),.ENABLE_SD2(0),.BURST_MAX_MHZ(16)) host(
 .CLK(clk_25),.N_RESET(locked),.MCU_MOSI(MCU_MOSI),.MCU_MISO(MCU_MISO),
 .MCU_SCK(MCU_SCK),.MCU_SS(MCU_CS_N),.MCU_SPI_FT_SS(1'b1),.MCU_SPI_SD2_SS(1'b1),
 .MCU_BURST_CS_N(MCU_BURST_CS_N),.MCU_BURST_READY(MCU_BURST_READY),
 .KB_STATUS(kb[7:0]),.KB_DAT0(kb[15:8]),.KB_DAT1(kb[23:16]),.KB_DAT2(kb[31:24]),
 .KB_DAT3(kb[39:32]),.KB_DAT4(kb[47:40]),.KB_DAT5(kb[55:48]),
 .MS_X(mouse_rep_dx),.MS_Y(mouse_rep_dy),.MS_B(mouse_buttons),.MS_UPD(mouse_rep_tgl),
 .SOFTSW_COMMAND(softsw_command),.OSD_COMMAND(osd_command),.BTNS(host_buttons),.BUSY(host_busy),
 .IMG_MOUNTED(img_mounted),.IMG_SIZE(img_size),.IMG_DATA_WR(img_data_wr),
 .IMG_DATA_ADDR(img_data_addr),.IMG_DATA(img_data),.IMG_RESULT_WR(img_result_wr),
 .IMG_RESULT(img_result),.IMG_SUM(img_sum),.IMG_Q_WR(img_q_wr),.IMG_Q_DI(img_q_di),.IMG_Q_ACK(img_q_ack),
 .RTC_A(8'd0),.RTC_DI(8'd0),.RTC_CS(1'b0),.RTC_WR_N(1'b1),
 .UART_TX_DATA(8'd0),.UART_TX_WR(1'b0),.UART_TX_MODE(1'b0),.UART_DLM(8'd0),.UART_DLL(8'd0),
 .UART_DLM_WR(1'b0),.UART_DLL_WR(1'b0),.FT_MISO(1'b1),.SD2_MISO(1'b1),
 .MATRIX_CMD(clock_message),.MATRIX_CMD_WR(clock_message_wr),.DEBUG_ADDR(16'd0),.DEBUG_DATA(16'd0)
);
mc0511_keyboard keyboard(.clk(clk_25),.reset(host_busy),.report(kb),.keycode(keycode));
wire [31:0] sd_img_size;
wire [63:0] mounted_size;
wire [7:0] mounted_slots;
wire [4:0] sd_img_mounted=mounted_slots[4:0];
assign sd_img_size=mounted_size[31:0];
wire sd_busy,sd_done,sd_rd_byte_strobe;
wire [8:0] sd_byte_index;
wire [7:0] sd_rd_data,sd_wr_data;
wire [4:0] sd_rd,sd_wr;
wire [31:0] sd_sector,fdd_sector;
wire [7:0] fdd_wr_data;
img_sdc #(.OUT_LATENCY(3),.TIMEOUT(24'd5000000)) storage(
 .clk(clk_25),.reset(~locked),.img_mounted(img_mounted),.img_size(img_size),
 .img_data_wr(img_data_wr),.img_data_addr(img_data_addr),.img_data(img_data),
 .img_result_wr(img_result_wr),.img_result(img_result),.img_sum(img_sum),
 .img_q_wr(img_q_wr),.img_q_di(img_q_di),.img_q_ack(img_q_ack),
 .sdc_img_mounted(mounted_slots),.sdc_img_size(mounted_size),
 .sdc_rd({3'd0,sd_rd}),.sdc_wr({3'd0,sd_wr}),.sdc_sector(sd_sector),
 .sdc_busy(sd_busy),.sdc_done(sd_done),.sdc_byte_in_strobe(sd_rd_byte_strobe),
 .sdc_byte_addr(sd_byte_index),.sdc_byte_in_data(sd_rd_data),.sdc_byte_out_data(sd_wr_data)
);
reg [4:0] mount_dsk=0;
reg [31:0] hdd_sectors=0;
always @(posedge clk_25) if(sd_img_mounted[4]) hdd_sectors<=sd_img_size>>9;
integer mount_i;
always @(posedge clk_25)
 for(mount_i=0;mount_i<5;mount_i=mount_i+1)
  if(sd_img_mounted[mount_i]) mount_dsk[mount_i] <= |sd_img_size;
// SWITCHES_INCLUDE
wire [15:0] rtc_year;
wire [3:0] rtc_month,rtc_dow;
wire [4:0] rtc_date,rtc_hour;
wire [5:0] rtc_min,rtc_sec;
wire [2:0] red_m=system_video?blue:red;
wire [2:0] blue_m=system_video?red:blue;
wire [23:0] machine_rgb=visible?{red_m,red_m,red_m[2:1],green,green,green[2:1],blue_m,blue_m,blue_m[2:1]}:24'd0;
kg_osd_overlay #(.H_OFFSET(104),.V_OFFSET(54)) osd(
 .clk(clkram),.rgb_i(machine_rgb),.rgb_o(rgb),.hsync_i(hsync),.vsync_i(vsync),.osd_command(osd_command)
);

// Eight read-back fields per second, snapshotted before transmission.
// A field every 256 host clocks avoids collisions with normal MCU traffic.
reg [24:0] clock_poll=0;
reg [63:0] clock_snapshot=0;
reg [23:0] clock_message=0;
reg clock_message_wr=0;
always @(posedge clk_25) begin
 clock_message_wr<=0;
 if(clock_poll==24999999)clock_poll<=0;else clock_poll<=clock_poll+1'b1;
 if(clock_poll==0)clock_snapshot<={4'd0,rtc_dow,2'd0,rtc_sec,2'd0,rtc_min,3'd0,rtc_hour,3'd0,rtc_date,4'd0,rtc_month,rtc_year};
 if(clock_poll>=256 && clock_poll<=2048 && clock_poll[7:0]==0)begin
  clock_message<={8'hf6,5'd0,clock_poll[10:8]-3'd1,clock_snapshot[7:0]};
  clock_snapshot<={8'd0,clock_snapshot[63:8]};
  clock_message_wr<=1;
 end
end
