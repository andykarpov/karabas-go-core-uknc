wire physical_selected=system_physical_fdd>=1 && system_physical_fdd<=4 &&
                       {1'b0,disk_drive}==system_physical_fdd-3'd1;
wire [15:0] virtual_fdd_data,physical_fdd_data;
wire [3:0] image_fdd_rd,image_fdd_wr;
assign fdd_rd=(physical_selected || !system_fdd_en)?4'd0:image_fdd_rd;
assign fdd_wr=(physical_selected || !system_fdd_en)?4'd0:image_fdd_wr;
assign ppu_wbm_dat_i_128=physical_selected?physical_fdd_data:virtual_fdd_data;
mc0511_physical_fdd physical_fdd(
 .clk(clk_25),.reset(ppu_vm_init_o || host_busy || !locked || !system_fdd_en),
 .selected(physical_selected),.motor(disk_motor),.step(disk_step),
 .dir(disk_dir),.head(disk_head),.write_protect(system_floppy_wprot[disk_drive]),
 .bus_addr(ppu_wbm_adr_o),.bus_data(ppu_wbm_dat_o),
 .bus_stb(ppu_wbm_stb_o),.bus_write(ppu_wbm_wre_o),.bus_ack(ppu_wbm_ack_i_128),.bus_out(physical_fdd_data),
 .index_in(FDC_INDEX),.track0_in(FDC_TR00),.protect_in(FDC_WPRT),.rdata_in(FDC_RDATA),
 .drive_out(FDC_DRIVE),.motor_out(FDC_MOTOR),.dir_out(FDC_DIR),.step_out(FDC_STEP),
 .side_out(FDC_SIDE_N),.wgate_out(FDC_WGATE),.wdata_out(FDC_WDATA));
