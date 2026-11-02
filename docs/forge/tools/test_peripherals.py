#!/usr/bin/env python3
"""Long source regressions, compiled against ported devices with Verilator."""
from prepare import ROOT,FORGE,OUT,TANG
from forge import run
import json,re
sources=json.loads((OUT/'sources.json').read_text())
for name in ('tb_aberrant','tb_kakave'):
    source=(TANG/'sim/tb'/f'{name}.v').read_text()
    # The KG1 PPU runs at exactly 3.125 MHz, so seven seconds is 21,875,000 edges.
    source=source.replace('21937500','21875000')
    if name=='tb_kakave':
        source=re.sub(r'    fork.*?    join', "    begin : ticks_count\n     integer ticks; ticks=0;\n     while(ticks<7)begin @(posedge clk);cycles=cycles+1;#1;if(dut.tick)ticks=ticks+1;end\n    end",source,count=1,flags=re.S)
    tb=OUT/(name+'.v');tb.write_text(source)
    extra=[TANG/'tang/src/mister/hid.v'] if name=='tb_kakave' else []
    run([FORGE/'bin/hdl/usr/bin/verilator','--binary','--timing','-Wno-fatal','--top-module',name,'-j','4','-Iupstream/modules/mcu','--Mdir',name+'_obj','-o','test',*sources,*extra,ROOT/'tests/xilinx_sim.v',tb],name+'-compile.log')
    run([OUT/(name+'_obj/test')],name+'.log')
    print((OUT/(name+'.log')).read_text()[-2000:])
