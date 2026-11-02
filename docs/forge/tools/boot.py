#!/usr/bin/env python3
from prepare import ROOT,FORGE,OUT
from forge import run
import json,sys
sources=json.loads((OUT/'sources.json').read_text())
run([FORGE/'bin/hdl/usr/bin/verilator','--binary','--timing','-Wno-fatal','--top-module','tb_boot','-j','4','-Iupstream/modules/mcu','-I'+str(ROOT/'tests'),'--Mdir','boot_obj','-o','boot','-CFLAGS','-O2',*sources,ROOT/'tests/xilinx_sim.v',ROOT/'tests/sdram_model.v',ROOT/'tests/tb_boot.v'],'boot-compile.log')
if '--compile-only' in sys.argv:sys.exit(0)
run([OUT/'boot_obj/boot',*sys.argv[1:]],'boot.log')
print((OUT/'boot.log').read_text()[-3000:])
