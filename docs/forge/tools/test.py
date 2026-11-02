#!/usr/bin/env python3
"""Run the source device regressions against the actual KG1 memories and adapters."""
import argparse,json,subprocess,re
from pathlib import Path
from prepare import ROOT,FORGE,OUT,TANG
from forge import run

def bench(name,source):
    src=json.loads((OUT/'sources.json').read_text())
    output=OUT/(name+'.vvp')
    run([FORGE/'bin/hdl/usr/bin/iverilog','-B',FORGE/'bin/hdl/usr/lib/x86_64-linux-gnu/ivl','-g2012','-s',name,'-I','upstream/modules/mcu','-I',ROOT/'tests','-o',output,*src,ROOT/'tests/xilinx_sim.v',ROOT/'tests/sdram_model.v',source],name+'-compile.log')
    run([FORGE/'bin/hdl/usr/bin/vvp',output],name+'.log')
    log=(OUT/(name+'.log')).read_text()
    print(log[-1800:])
    if re.search(r'\bFAIL\b|\b[1-9][0-9]* error\(s\)',log):raise RuntimeError(name+' reported a failure')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('suite',nargs='?',default='quick');a=p.parse_args()
    if a.suite=='quick':
        bench('tb_osd',ROOT/'tests/tb_osd.v')
        bench('tb_board_link',ROOT/'tests/tb_board_link.v')
        bench('tb_physical_fdd',ROOT/'tests/tb_physical_fdd.v')
        bench('tb_keyboard_adapter',ROOT/'tests/tb_keyboard_adapter.v')
        for name in ['tb_covox','tb_hwen','tb_sdarb','tb_kbd','tb_virq','tb_ide','tb_mixer']:
            bench(name,TANG/'sim/tb'/f'{name}.v')
    else:bench(a.suite,ROOT/'tests'/f'{a.suite}.v')
