`timescale 1ns/1ps
// GO B4 wiring: RP2040 IO0 / GPIO14 -> FPGA MCU_SPI_IO[1] (M11),
// RP2040 IO1 / GPIO2 -> FPGA MCU_SPI_IO[0] (N9). Model firmware pulls.
module tb_board_link;
reg clk=0; always #10 clk=~clk;
reg sck=0,cs=1,mosi=0,burst_drive=0,burst_cs=1;
tri [1:0] io;
pullup(io[1]); pulldown(io[0]);
assign io[1]=burst_drive?burst_cs:1'bz;
wire miso;
wire [1:0] fdc_drive;
wire fdc_motor,fdc_step,fdc_wgate,fdc_wdata;
wire mosi_pin=mosi;
karabas_go_top uut(.CLK_50MHZ(clk),.MCU_SCK(sck),.MCU_CS_N(cs),
 .MCU_MOSI(mosi_pin),.MCU_MISO(miso),.MCU_SPI_IO(io),
 .MCU_SPI_FT_CS_N(1'b1),.MCU_SPI_SD2_CS_N(1'b1),
 .FDC_DRIVE(fdc_drive),.FDC_MOTOR(fdc_motor),.FDC_STEP(fdc_step),
 .FDC_WGATE(fdc_wgate),.FDC_WDATA(fdc_wdata),
 .FDC_INDEX(1'b0),.FDC_TR00(1'b1),.FDC_WPRT(1'b0),.FDC_RDATA(1'b0));
reg [23:0] reply;
task frame(input [23:0] word);
 integer b;
 begin
 reply=0;cs=0;#200;
 for(b=23;b>=0;b=b-1)begin
  mosi=word[b];#32;reply={reply[22:0],miso};sck=1;#32;sck=0;
 end
 #200;cs=1;#5000;
 end
endtask
task byte_out(input [7:0] value);
 integer b;
 begin for(b=7;b>=0;b=b-1)begin mosi=value[b];#32;sck=1;#32;sck=0;end end
endtask
integer n,bytes_seen=0;
integer map_value,drive_value;
reg [1:0] drive_probe=0;
always @(posedge uut.machine.clk_25)if(uut.machine.img_data_wr)begin
 if(uut.machine.img_data_addr!==bytes_seen || uut.machine.img_data!==8'ha0+bytes_seen)
  $fatal(1,"Burst payload/address mismatch at byte %0d",bytes_seen);
 bytes_seen=bytes_seen+1;
end
initial begin
 #10000;
 if({fdc_drive,fdc_motor,fdc_step,fdc_wgate,fdc_wdata}!==6'd0)
  $fatal(1,"Physical floppy active at configuration default None");
 frame(24'hf70001);
 for(n=0;n<16 && reply[23:16]!==8'hf7;n=n+1)frame(0);
 if(reply!==24'hf70310)$fatal(1,"No board-pin CAPS reply: %h",reply);
 if(io[0]!==1'b1)$fatal(1,"READY missing on FPGA IO[0]");
 frame(24'hfd0000);frame(24'h200101);
 if(uut.machine.osd.osd_overlay!==1)$fatal(1,"OSD command blocked");
 frame(24'hfe0000);
 if(uut.machine.host_busy!==0)$fatal(1,"INIT_DONE did not release machine reset");
 burst_drive=1;#1000;burst_cs=0;#200;
 byte_out(8'h45);repeat(4)byte_out(0);
 for(n=0;n<4;n=n+1)byte_out(8'ha0+n);
 #400;burst_cs=1;#1000;
 if(bytes_seen!=4)$fatal(1,"Burst select did not deliver four bytes: %0d",bytes_seen);
 // Pin/mux test with the machine controls held independently of the CPUs.
 // Configuration still travels through the actual RP2040 SPI soft-switch path.
 force uut.machine.ppu_vm_init_o=0;
 force uut.machine.disk_motor=1;
 force uut.machine.disk_drive=drive_probe;
 force uut.machine.image_fdd_rd=4'b1111;
 for(map_value=0;map_value<=4;map_value=map_value+1)begin
  frame({8'h05,8'd27,map_value[7:0]});
  for(drive_value=0;drive_value<4;drive_value=drive_value+1)begin
   drive_probe=drive_value;#1000;
   if(map_value!=0 && drive_value==map_value-1)begin
    if(fdc_drive!==1 || fdc_motor!==1 || uut.machine.fdd_rd!==0)
     $fatal(1,"Physical slot did not select pins and suppress image requests");
   end else if(fdc_drive!==0 || fdc_motor!==0 || uut.machine.fdd_rd!==4'b1111)
    $fatal(1,"Virtual slot did not release physical pins and retain image requests");
  end
 end
 frame({8'h05,8'd19,8'd0});
 if(fdc_motor!==0 || fdc_drive!==0 || uut.machine.fdd_rd!==0)$fatal(1,"FDD Off did not inhibit both backends");
 frame({8'h05,8'd19,8'd1});
 frame({8'h05,8'd27,8'd255});
 if(uut.machine.system_physical_fdd!==0 || fdc_motor!==0 || fdc_drive!==0)
  $fatal(1,"Invalid physical choice did not fall back to None");
 release uut.machine.ppu_vm_init_o;
 release uut.machine.disk_motor;
 release uut.machine.disk_drive;
 release uut.machine.image_fdd_rd;
 frame(24'hfd0000);
 if(uut.machine.host_busy!==1)$fatal(1,"Classic frames failed after burst");
 $display("PASS: GO pin CAPS, READY, OSD, reset, burst, physical FDD SPI mapping/idle and image isolation");
 $finish;
end
endmodule
