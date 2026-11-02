#!/usr/bin/env python3
"""Check the real GO clock forwarder with the source I2S serializer."""
from prepare import ROOT,OUT
from test import bench
line=next(x for x in (ROOT/'src/rtl/karabas_go_top.v').read_text().splitlines() if x.startswith('ODDR2 dac_clock('))
(OUT/'upstream/modules/mcu/board_dac_clock.vh').write_text(line+'\n')
try:bench('tb_audio_pins',ROOT/'tests/tb_audio_pins.v')
finally:(OUT/'upstream/modules/mcu/board_dac_clock.vh').unlink(missing_ok=True)
