`timescale 1ns/1ps
module tb_boot;
reg clk=0;always #10 clk=~clk;
reg ramclk=0;initial begin #3.125;forever #10 ramclk=~ramclk;end
reg cpuclk=0;initial begin #10;cpuclk=1;forever #120 cpuclk=~cpuclk;end
reg hostclk=0;initial begin #30;hostclk=1;forever #20 hostclk=~hostclk;end
reg ppuclk=0;initial begin #10;ppuclk=1;forever #160 ppuclk=~ppuclk;end
reg locked=0;initial #1000 locked=1;
reg sck=0,ss=1,mosi=0,burst_cs=1;wire miso;
wire [10:0] ra;wire [1:0] ba,dqm;wire [15:0] dq;wire cs,ras,cas,we;
wire [23:0] rgb;wire hs,vs,visible;
`include "physical_media.vh"
mc0511_machine uut(.clkram(clk),.clk4(cpuclk),.clk_25(hostclk),.clk_3_12(ppuclk),.locked(locked),
 .O_sdram_addr(ra),.IO_sdram_dq(dq),.O_sdram_ba(ba),.O_sdram_dqm(dqm),
 .O_sdram_cs_n(cs),.O_sdram_wen_n(we),.O_sdram_ras_n(ras),.O_sdram_cas_n(cas),
 .MCU_SCK(sck),.MCU_CS_N(ss),.MCU_MOSI(mosi),.MCU_MISO(miso),.MCU_BURST_CS_N(burst_cs),
 .rgb(rgb),.hsync(hs),.vsync(vs),.visible(visible),.uart_rx(1'b1),
 .FDC_INDEX(physical_index),.FDC_TR00(physical_track0),.FDC_WPRT(1'b1),.FDC_RDATA(physical_flux),
 .FDC_DRIVE(physical_ds),.FDC_MOTOR(physical_motor),.FDC_DIR(physical_dir),.FDC_STEP(physical_step),
 .FDC_SIDE_N(physical_side),.FDC_WGATE(physical_wgate),.FDC_WDATA(physical_wdata));
sdram_model ram(.clk(ramclk),.cke(1'b1),.cs_n(cs),.ras_n(ras),.cas_n(cas),.we_n(we),.ba(ba),.a(ra),.dqm_l(dqm[0]),.dqm_h(dqm[1]),.dq(dq));
`include "host_media.vh"
task frame(input [23:0] word);
 integer bitno;
 begin
 spi_reply=0;ss=0;#200;
 for(bitno=23;bitno>=0;bitno=bitno-1)begin mosi=word[bitno];#32;spi_reply={spi_reply[22:0],miso};sck=1;#32;sck=0;end
 #200;ss=1;#400;reply_frame(spi_reply);
 end
endtask
integer ppu_ops=0,cpu_ops=0,lit=0,frames=0;
always @(posedge uut.askn_ppu_i)ppu_ops=ppu_ops+1;
always @(posedge uut.askn_cpu_i)cpu_ops=cpu_ops+1;
always @(posedge clk)if(visible && rgb!=0)lit=lit+1;
always @(posedge vs)frames=frames+1;
reg [23:0] frame_pixels[0:383999];
always @(posedge clk) if(visible && uut.ram1.horz[0])
 frame_pixels[uut.ram1.vert*640+(uut.ram1.horz-16)/2]<=rgb;
integer ppm,px,physical_fd,physical_size;
integer ms=1500;
integer extra_key=0,key_after_ms=2000;
string frame_path="boot.ppm";
always begin #1000000000;$display("PROGRESS %t frames=%0d sectors=%0d errors=%0d",$time,frames,media_reads,mem_errs);$fflush();end
initial begin
 if($value$plusargs("RUN_MS=%d",ms))begin end
 if($value$plusargs("FRAME=%s",frame_path))begin end
 if($value$plusargs("KEY=%h",extra_key))begin end
 if($value$plusargs("KEY_AFTER_MS=%d",key_after_ms))begin end
 #1500000;frame(24'hfd0000);frame(24'hfe0000);
 if($value$plusargs("PHYS_DSK=%s",media_path))begin
  physical_fd=$fopen(media_path,"rb");if(!physical_fd)$fatal(1,"Cannot open physical DSK");
  physical_size=$fread(physical_image,physical_fd);$fclose(physical_fd);
  if(physical_size!=819200)$fatal(1,"Expected 800 KiB physical DSK");
  physical_present=1;frame({8'h05,8'd27,8'd1});
  media_wait(1500);media_key(8'h1e);media_key(8'h28);media_wait(ms);
  $display("PHYSICAL words=%0d track=%0d rotations=%0d image requests=%0d",physical_words,physical_track,physical_sectors/10,media_reads);
  if(physical_words<256 || media_reads!=0)$fatal(1,"Physical boot did not read through cable pins");
 end else if($value$plusargs("DSK=%s",media_path))begin
  mount_media(0);
  if($value$plusargs("SECOND_HDD=%s",media_path))mount_media(4);
  media_wait(1500);media_key(8'h1e);media_key(8'h28);media_wait(ms);
  $display("MEDIA reads=%0d",media_reads);
  if(media_reads<10)$fatal(1,"Disk boot did not read sectors");
 end else if($value$plusargs("HDD=%s",media_path))begin
  mount_media(4);media_wait(1500);media_key(8'h1f);media_key(8'h28);
  if(extra_key)begin
   media_wait(key_after_ms);media_key(extra_key[7:0]);media_key(8'h28);
  end
  media_wait(ms);
  $display("HDD MEDIA reads=%0d writes=%0d (writes are RAM-only)",media_reads,media_writes);
  if(media_reads<1)$fatal(1,"HDD boot did not read sectors");
 end else #(ms*64'd1000000);
 ppm=$fopen(frame_path,"wb");$fwrite(ppm,"P6\n640 600\n255\n");
 for(px=0;px<384000;px=px+1)$fwrite(ppm,"%c%c%c",frame_pixels[px][23:16],frame_pixels[px][15:8],frame_pixels[px][7:0]);
 $fclose(ppm);
 $display("BOOT frames=%0d lit=%0d PPU=%0d CPU=%0d memory checks=%0d errors=%0d",frames,lit,ppu_ops,cpu_ops,mem_checks,mem_errs);
 if(mem_errs || mem_checks<100 || cpu_ops<100 || ppu_ops<100 || lit<100)$fatal(1,"Machine boot evidence failed");
 $finish;
end
    // Byte-enable-aware scoreboard, shared by CPU and PPU. Bank 0 uses
    // byte addresses; bank 1 uses word addresses on both processor ports.
    reg [7:0] shadow[0:262143];
    reg known[0:262143];
    integer mem_errs=0,mem_checks=0,si;
    initial for(si=0;si<262144;si=si+1)known[si]=0;
    task mem_watch(input is_cpu,input [15:0] adr,input wr,input [3:0] msk,input [31:0] dat);
      integer lane,index;
      reg [7:0] value;
      begin
       for(lane=0;lane<4;lane=lane+1)if(!msk[lane])begin
        index=lane<2 ? ((adr & 16'hfffe)+(lane%2)) : (131072+adr*2+(lane%2));
        value=dat>>(lane*8);
        if(wr)begin shadow[index]=value;known[index]=1;end
        else if(known[index])begin
         mem_checks=mem_checks+1;
         if(value!==shadow[index])begin
          mem_errs=mem_errs+1;
          if(mem_errs<=10)$display("[mem] %t %s byte%0d at %o got %h want %h physical=%h latched cpu=%o ppu=%o q=%d CPU rd/wr=%b%b latched=%b%b",$time,is_cpu?"cpu":"ppu",lane,adr,value,shadow[index],ram.mem[(lane<2?0:524288)+(lane<2?adr/2:adr)],uut.ram1.cpu_addr_new,uut.ram1.ppu_addr_new,uut.ram1.q,uut.read_cpu_o,uut.wrte_cpu_o,uut.ram1.cpu_read_new,uut.ram1.cpu_wrte_new);
          if($test$plusargs("STOP_MEM_ERROR"))$fatal(1,"First memory mismatch");
         end
        end
       end
      end
    endtask

    // The source controller may complete a sampled write after the requester
    // has dropped its strobe. No read response is consumed on that idle bus.
    // Do not misinterpret an idle completion as a read of the old address.
    always @(posedge uut.askn_ppu_i)
        if (!$test$plusargs("NOMEMCHECK") && (uut.read_ppu_o || uut.wrte_ppu_o))
            mem_watch(1'b0, uut.addr_ppu_o, uut.wrte_ppu_o, uut.mask_ppu_o,
                      uut.wrte_ppu_o ? uut.data_ppu_o : uut.data_ppu_i);
    always @(posedge uut.askn_cpu_i)
        if (!$test$plusargs("NOMEMCHECK") && (uut.read_cpu_o || uut.wrte_cpu_o))
            mem_watch(1'b1, uut.addr_cpu_o, uut.wrte_cpu_o, uut.mask_cpu_o,
                      uut.wrte_cpu_o ? uut.data_cpu_o : uut.data_cpu_i);


endmodule
