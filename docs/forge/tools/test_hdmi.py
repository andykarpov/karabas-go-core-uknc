#!/usr/bin/env python3
"""Check actual UKNC HDMI audio packets and genuine Spartan-6 DCM startup."""
import argparse,json,hashlib
import forge
from prepare import ROOT,FORGE

def test(board):
    forge.select_board(board);out=forge.OUT;hdl=FORGE/'bin/hdl/usr'
    translated=forge.simulation_hdmi()
    forge.run([hdl/'bin/iverilog','-B',hdl/'lib/x86_64-linux-gnu/ivl','-g2012','-s','tb_hdmi_clock','-o','hdmi-clock.vvp',out/'rtl/mc0511_hdmi.v',ROOT/'tests/xilinx_sim.v',ROOT/'tests/tb_hdmi_clock.v',*translated],'hdmi-clock-compile.log')
    forge.run([hdl/'bin/vvp','hdmi-clock.vvp'],'hdmi-clock.log')
    print((out/'hdmi-clock.log').read_text()[-700:])
    obj=out/'verilator_hdmi'
    forge.run([hdl/'bin/verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','tb_hdmi_audio_packets','--Mdir',obj,
               ROOT/'tests/tb_hdmi_audio_packets.v',ROOT/'tests/xilinx_sim.v',ROOT/'tests/hdmi_clock_model.v',
               out/'rtl/mc0511_hdmi.v',out/'upstream/tang/sdram2.v',*translated[:2]],'hdmi-packet-compile.log')
    forge.run([obj/'Vtb_hdmi_audio_packets'],'hdmi-packet.log')
    logs={name: (out/name).read_text() for name in ('hdmi-clock.log','hdmi-packet.log')}
    for name,log in logs.items():
        if 'PASS HDMI' not in log:raise RuntimeError(log)
    print(logs['hdmi-packet.log'])
    (out/'hdmi-test.json').write_text(json.dumps(dict(board=board,passed=True,manifest_sha256=hashlib.sha256((out/'manifest.json').read_bytes()).hexdigest(),logs_sha256={n:hashlib.sha256(t.encode()).hexdigest() for n,t in logs.items()},coverage='Actual UKNC raster and HDMI PCM sampler/packets: stereo payload, ordering, parity, queue, 48 kHz rate, ACR; vendor DCM startup/relock. No electrical HDMI capture.'),indent=2)+'\n')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--board',choices=['mini','minig'],required=True);test(p.parse_args().board)
