#!/usr/bin/env python3
"""Verify generated OSD batching and progress under continuous UI input."""
import subprocess
from prepare import ROOT

build = ROOT/'build/ui-progress-tests'
build.mkdir(parents=True, exist_ok=True)
src = ROOT/'build/firmware'
(build/'Arduino.h').write_text('#pragma once\n#include <stdint.h>\n#include <stddef.h>\nclass Print { public: virtual size_t write(uint8_t)=0; };\n')
(build/'OSD.h').write_text((src/'lib/OSD/OSD.h').read_text())
s = (src/'lib/OSD/OSD.cpp').read_text()
body = s[s.index('const uint8_t CMD_OSD'):s.index('void OSD::frame(')]
body += s[s.index('size_t OSD::write('):s.index('void OSD::showMenu(')]
(build/'osd_frame_under_test.inc').write_text(body)
s = (src/'src/input/input.cpp').read_text()
(build/'ui_dispatch_under_test.inc').write_text(s[s.index('void input_tick_ui()'):s.index('bool on_global_hotkeys()')])
for name in ['osd_frame', 'ui_dispatch']:
    subprocess.run(['g++', '-std=c++11', '-Wall', '-Wextra', '-Werror', '-I'+str(build),
                    str(ROOT/f'tests/{name}.cpp'), '-o', str(build/name)], check=True)
    subprocess.run([str(build/name)], check=True)
print('PASS APP returns under continuous input, catches up, acknowledges hotkeys and handles counter wrap')
