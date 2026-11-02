#!/usr/bin/env python3
"""Boot the full UKNC from read-only pin-level MFM media, without an SD server.

Reuse the machine/SDRAM scoreboard from tb_boot, but omit the large image-server
coroutines so the physical-only harness compiles independently and quickly.
"""
import argparse,json,subprocess,sys
from prepare import ROOT,FORGE,OUT
from forge import run
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--compile-only',action='store_true')
p.add_argument('--run-ms',type=int,default=10000)
p.add_argument('--trace',action='store_true')
a=p.parse_args()
s=(ROOT/'tests/tb_boot.v').read_text().replace('module tb_boot;','module tb_physical_boot;')
s=s.replace('`include "host_media.vh"','''reg [23:0] spi_reply;
integer media_reads=0;
string media_path;
task reply_frame(input [23:0] value);
 if(value[23:16]==8'h43)$fatal(1,"Unexpected image request during physical boot");
endtask
task media_wait(input integer duration_ms);
 #(duration_ms*64'd1000000);
endtask
task media_key(input [7:0] key);
 begin frame({8'h01,8'h01,key});media_wait(40);frame(24'h010100);media_wait(40);end
endtask
always @(posedge hostclk)begin
 if(physical_present && (|uut.fdd_rd || |uut.fdd_wr))$fatal(1,"Physical slot requested image data");
 if($test$plusargs("FDD_TRACE") && uut.physical_fdd.command)
  $display("FDD_CMD %t %h drive=%d motor=%b step=%b dir=%b head=%b track=%d",$time,
   uut.ppu_wbm_dat_o,uut.disk_drive,uut.disk_motor,uut.disk_step,uut.disk_dir,uut.disk_head,physical_track);
end
''')
begin=s.index(' end else if($value$plusargs("DSK=%s",media_path))begin')
end=s.index(' ppm=$fopen',begin)
s=s[:begin]+' end else $fatal(1,"PHYS_DSK is required");\n'+s[end:]
s=s.replace('frames,media_reads,mem_errs);','frames,media_reads,mem_errs);$display("PHYSICAL track=%d head=%b words=%d ready=%b crc=%b",physical_track,physical_side,physical_words,uut.physical_fdd.spinup==12500000,uut.physical_fdd.rx_crc);')
tb=OUT/'tb_physical_boot.v';tb.write_text(s)
sources=json.loads((OUT/'sources.json').read_text())
run([FORGE/'bin/hdl/usr/bin/verilator','--binary','--timing','-Wno-fatal','--top-module','tb_physical_boot','-j','4','-Iupstream/modules/mcu','-I'+str(ROOT/'tests'),'--Mdir','physical_boot_obj','-o','boot','-CFLAGS','-O2',*sources,ROOT/'tests/xilinx_sim.v',ROOT/'tests/sdram_model.v',tb],'physical-boot-compile.log')
if a.compile_only:sys.exit(0)
dest=ROOT/'build/physical-fdd';dest.mkdir(exist_ok=True)
command=[OUT/'physical_boot_obj/boot',f'+PHYS_DSK={ROOT}/res/media/RT11BASE.DSK',f'+RUN_MS={a.run_ms}',f'+FRAME={dest}/boot.ppm']
if a.trace:command+=['+FDD_TRACE']
with (dest/'boot.log').open('w') as f:subprocess.run(list(map(str,command)),cwd=OUT,stdout=f,stderr=subprocess.STDOUT,check=True)
print((dest/'boot.log').read_text()[-2000:])
