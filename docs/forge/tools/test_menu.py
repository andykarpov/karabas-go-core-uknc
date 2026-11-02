#!/usr/bin/env python3
"""Host execution of the actual firmware menu against the actual core configuration."""
import json,subprocess
from prepare import ROOT
out=ROOT/'build/menu-test';out.mkdir(parents=True,exist_ok=True)
items=json.loads((ROOT/'config/core.json').read_text())['osd']
types=dict(H='HIDDEN',P='TEXT',F='FILEMOUNTER',FL='FILELOADER',T='TRIGGER',S='SWITCH')
lines=['void configure(){',f'core.osd_len={len(items)};']
for i,it in enumerate(items):
 lines.append(f'core.osd[{i}]={{CORE_OSD_TYPE_{types[it["type"]]},{json.dumps(it["name"])},{json.dumps(it.get("hotkey",""))},{len(it.get("options",[]))},{it.get("default",0)},{it.get("slot",0)},{{}}}};')
 for j,option in enumerate(it.get('options',[])):lines.append(f'core.osd[{i}].options[{j}].name={json.dumps(option)};')
lines.append('}')
(out/'menu_config.inc').write_text('\n'.join(lines)+'\n')
subprocess.run(['g++','-std=c++17','-Wall','-Wextra','-I'+str(ROOT/'firmware'),'-I'+str(out),str(ROOT/'tests/menu_host.cpp'),'-o',str(out/'test')],check=True)
with (out/'screens.txt').open('w') as f:subprocess.run([str(out/'test')],stdout=f,check=True)
print((out/'screens.txt').read_text().splitlines()[-1])
