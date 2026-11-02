#!/usr/bin/env python3
"""Exercise the generated firmware's real USB-export reboot routine."""
import subprocess
from prepare import ROOT
build=ROOT/'build'
s=(build/'firmware/src/storage/msc.cpp').read_text()
body=s[s.index('void msc_reboot_to_msc('):s.index('void msc_check_boot(')]
(build/'msc_reboot_under_test.inc').write_text(body)
subprocess.run(['g++','-std=c++11','-Wall','-Wextra','-I'+str(build),str(ROOT/'tests/sd_reboot.cpp'),'-o',str(build/'sd_reboot')],check=True)
subprocess.run([str(build/'sd_reboot')],check=True)
