#!/usr/bin/env python3
"""Collect a timing-accepted FPGA package and matching board-specific RP2040 firmware."""
import argparse,hashlib,json,shutil
import forge,firmware
from prepare import ROOT
from port_boards import BOARDS

def bundle(board):
    forge.select_board(board);forge.package()
    firmware.prepare()
    record_name='firmware-completed.json' if board=='go' else f'firmware-{board}-completed.json'
    evidence=json.loads((ROOT/'build'/record_name).read_text())
    if firmware.source_hashes()!=evidence['sources']:raise RuntimeError('Firmware source changed since build')
    uf2=firmware.DST/f'.pio/build/{board}/firmware.uf2'
    if hashlib.sha256(uf2.read_bytes()).hexdigest()!=evidence['uf2_sha256']:raise RuntimeError('Firmware binary changed')
    extension=BOARDS[board];out=ROOT/'bin'/extension;out.mkdir(parents=True,exist_ok=True)
    names=[f'mc0511.{extension}',f'mc0511-{board}-firmware.uf2']
    for src,name in zip([forge.OUT/names[0],uf2],names):shutil.copyfile(src,out/name)
    files={name:dict(bytes=(out/name).stat().st_size,sha256=hashlib.sha256((out/name).read_bytes()).hexdigest()) for name in names}
    manifest=dict(board=board,status='hardware acceptance pending',build=json.loads((forge.OUT/'core.json').read_text())['build'],files=files,
                  fpga=json.loads((forge.OUT/'ise-completed.json').read_text()))
    acceptance=ROOT/'docs/evidence/hdd-26103102.json'
    if board=='go' and acceptance.exists():
        record=json.loads(acceptance.read_text())
        if record['firmware_sha256']==files[names[1]]['sha256'] and record['kg1_sha256']==files[names[0]]['sha256']:
            manifest['status']='targeted HDD/audio/menu acceptance passed; other hardware checks remain pending'
            manifest['hdd_acceptance']=record
    for name in ('board-test.json','hdmi-test.json'):
        path=forge.OUT/name
        if path.exists():
            record=json.loads(path.read_text())
            if record['manifest_sha256']==manifest['fpga']['manifest_sha256']:manifest[name[:-5]]=record
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(out)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board',choices=[*BOARDS,'all'],default='go')
    args=parser.parse_args()
    for board in BOARDS if args.board=='all' else [args.board]:bundle(board)
