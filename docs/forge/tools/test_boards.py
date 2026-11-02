#!/usr/bin/env python3
"""Exercise actual Mini top-level MCU pins, OSD/reset, burst data and absent FDD."""
import argparse,re,json,hashlib
import forge
from prepare import ROOT,FORGE

def test(board):
    forge.select_board(board);out=forge.OUT
    forge.elaborate()
    bench=(ROOT/'tests/tb_board_link.v').read_text()
    bench=bench.replace('karabas_go_top',forge.TARGET+'_top')
    bench=bench.replace('tri [1:0] io;', 'tri [5:0] io;')
    bench=bench.replace('io[1]', 'io[CS]').replace('io[0]', 'io[1]').replace('io[CS]', 'io[0]')
    bench=bench.replace('.MCU_SPI_IO(io)', '.MCU_IO(io'+('[3:0]' if board=='mini' else '')+')')
    bench=re.sub(r' \.MCU_SPI_FT_CS_N.*?\.FDC_RDATA\(1\'b0\)\);', ' .UART_RX());',bench,flags=re.S)
    bench=re.sub(r' if\(\{fdc_drive.*?configuration default None"\);', '',bench,flags=re.S)
    start=bench.index('   if(map_value!=0');end=bench.index('\n  end\n end',start)
    bench=bench[:start]+'''   if(uut.machine.physical_selected!==0 || uut.machine.fdd_rd!==4'b1111)
    $fatal(1,"Saved physical FDD setting must not suppress Mini image requests");'''+bench[end:]
    bench=bench.replace('fdc_motor!==0 || fdc_drive!==0 || ', '')
    bench=bench.replace(' || fdc_motor!==0 || fdc_drive!==0','')
    bench=bench.replace('GO pin CAPS','Mini pin CAPS').replace('physical FDD SPI mapping/idle and image isolation','saved absent FDD selection isolation')
    path=out/'tb_board_link_mini.v';path.write_text(bench)
    sources=[f for f in json.loads((out/'sources.json').read_text()) if f.endswith('.v')]
    forge.run([FORGE/'bin/hdl/usr/bin/iverilog','-B',FORGE/'bin/hdl/usr/lib/x86_64-linux-gnu/ivl','-g2012','-s','tb_board_link','-I','upstream/modules/mcu','-o','board-test.vvp',*sources,ROOT/'tests/xilinx_sim.v',*forge.simulation_hdmi(),path],'board-compile.log')
    forge.run([FORGE/'bin/hdl/usr/bin/vvp','board-test.vvp'],'board-test.log')
    log=(out/'board-test.log').read_text()
    if 'PASS: Mini pin CAPS' not in log:raise RuntimeError(log)
    (out/'board-test.json').write_text(json.dumps(dict(board=board,passed=True,manifest_sha256=hashlib.sha256((out/'manifest.json').read_bytes()).hexdigest(),log_sha256=hashlib.sha256(log.encode()).hexdigest(),coverage='Actual board wrapper MCU pins, CAPS, READY, OSD, reset, sector burst and ignored saved physical FDD settings; simulation only'),indent=2)+'\n')
    print(log[-900:])
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--board',choices=['mini','minig'],required=True);test(p.parse_args().board)
