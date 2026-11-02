#!/usr/bin/env python3
"""Run source IDE bus cases through KG1 MCU SPI and checked sector transport."""
import json
from prepare import ROOT,FORGE,OUT,TANG
from forge import run
s=(TANG/'sim/tb/tb_ide.v').read_text().replace('module tb_ide;','module tb_ide_spi;')
s=s.replace('integer errors = 0;', "reg [31:0] image_sectors=32'h10000000;\ninteger errors = 0;")
s=s.replace('.hdd_present(present),','.hdd_present(present), .image_sectors(image_sectors),')
s=s.replace("reg         rbusy = 1'b0, rdone = 1'b0, outen = 1'b0;",'wire rbusy,rdone,outen;')
s=s.replace("reg  [ 8:0] outaddr = 9'd0;",'wire [8:0] outaddr;').replace("reg  [ 7:0] inbyte = 8'd0;",'wire [7:0] inbyte;')
a=s.index('always @(posedge clk) begin\n    rdone');b=s.index('// a PPU bus cycle',a)
s=s[:a]+(ROOT/'tests/ide_spi_host.vh').read_text()+'\n'+s[b:]
s=s.replace('t < 2000','t < 10000').replace('repeat (1500)', 'repeat (15000)')
s=s.replace('    $display("[tb_ide] %0d error(s)", errors);',(ROOT/'tests/ide_bounds.vh').read_text()+'\n    $display("[tb_ide] %0d error(s)", errors);')
s=s.replace('$finish;', 'if(errors)$fatal(1,\"IDE SPI regression failed\");$finish;')
tb=OUT/'tb_ide_spi.v';tb.write_text(s)
sources=json.loads((OUT/'sources.json').read_text())
run([FORGE/'bin/hdl/usr/bin/verilator','--binary','--timing','-Wno-fatal','--top-module','tb_ide_spi','-j','4','-Iupstream/modules/mcu','--Mdir','ide_spi_obj','-o','test',*sources,ROOT/'tests/xilinx_sim.v',tb],'ide-spi-compile.log')
run([OUT/'ide_spi_obj/test'],'ide-spi.log')
print((OUT/'ide-spi.log').read_text()[-3000:])
