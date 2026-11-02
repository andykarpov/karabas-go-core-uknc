#!/usr/bin/env python3
"""Native firmware regressions: path boundary, HDD headers and actual SAV volumes."""
from pathlib import Path
import hashlib,json,subprocess,sys
from prepare import ROOT,TANG,FORGE,verify_inputs
verify_inputs()
sys.path.insert(0,str(TANG/'tools'))
from rt11fs import Volume,E_PERM,BLOCK
build=ROOT/'build';build.mkdir(exist_ok=True)
def run(args):subprocess.run(list(map(str,args)),check=True)
common=FORGE/'external/karabas-go-firmware/lib/KarabasCommon/src'
run(['g++','-std=c++11','-Wall','-Wextra','-I'+str(common),ROOT/'tests/media_filters.cpp',common/'file_name.cpp','-o',build/'media_filters'])
media=[p.name for p in sorted((ROOT/'res/media').iterdir()) if p.is_file()]
config=json.loads((ROOT/'config/core.json').read_text())
for slot,expected in [(0,7),(1,7),(2,7),(3,7),(4,2),(5,2)]:
    item=next(x for x in config['osd'] if x.get('slot')==slot)
    # make_core stores 256 space-padded bytes; the MCU terminates byte 255.
    run([build/'media_filters',item['extensions'].ljust(256)[:255],expected,*media])
run(['g++','-std=c++11','-Wall','-Wextra','-I'+str(ROOT/'firmware'),ROOT/'tests/media_policy.cpp','-o',build/'media_policy'])
run([build/'media_policy',ROOT/'res/media/bappwd.img',ROOT/'res/media/WDC170inv_P.img'])
run(['cc','-std=c11','-Wall','-Wextra','-I'+str(build/'firmware/src'),ROOT/'tests/rt11_host.c',build/'firmware/src/rt11_volume.c','-o',build/'rt11_host'])
base=ROOT/'res/media/RT11BASE.DSK';original=base.read_bytes();original_volume=Volume(base)
for source in sorted((ROOT/'res/media').glob('*.SAV')):
    target=build/(source.stem+'.DSK')
    run([build/'rt11_host',base,source,target,source.name])
    vol=Volume(target)
    extracted=build/(source.name+'.extracted');vol.get(source.name,extracted)
    assert extracted.read_bytes()[:source.stat().st_size]==source.read_bytes()
    entry=vol.find('STARTS.COM');start=vol.img[entry.block*BLOCK:(entry.block+entry.length)*BLOCK].split(b'\0')[0]
    assert ('R '+source.stem).encode() in start
    assert vol.img[:6*BLOCK]==original[:6*BLOCK], 'Boot blocks changed'
    for old in original_volume.read_dir()[1]:
        if old.status&E_PERM and old.name not in ('STARTS.COM',source.name):
            new=vol.find(old.name)
            assert new.block==old.block and new.length==old.length,old.name
            assert vol.img[new.block*BLOCK:(new.block+new.length)*BLOCK]==original[old.block*BLOCK:(old.block+old.length)*BLOCK],old.name
    print('PASS',source.name,'exact payload, STARTS.COM, boot/system files and template intact')
assert base.read_bytes()==original
