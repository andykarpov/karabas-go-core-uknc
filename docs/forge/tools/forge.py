#!/usr/bin/env python3
"""Build, simulate and package UKNC MC-0511 for GO, Mini and Mini G."""
import argparse,hashlib,json,os,subprocess,sys
from pathlib import Path
import prepare as project
from prepare import ROOT,FORGE,OUT
TARGET="karabas_go"
EXTENSION="kg1"
def prepare(): project.main()
def select_board(board):
    global OUT,TARGET,EXTENSION
    project.select_board(board); OUT=project.OUT; TARGET=project.TARGET; EXTENSION=project.EXTENSION

def run(args,log=None,cwd=None):
    if cwd is None: cwd=OUT
    env=os.environ.copy(); env['LD_LIBRARY_PATH']=str(FORGE/'bin/hdl/usr/lib/x86_64-linux-gnu')+':'+env.get('LD_LIBRARY_PATH','')
    if log:
        with open(OUT/log,'w') as f:r=subprocess.run(list(map(str,args)),cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT)
        if r.returncode: print((OUT/log).read_text()[-6000:])
        r.check_returncode()
    else:subprocess.run(list(map(str,args)),cwd=cwd,env=env,check=True)

def simulation_hdmi():
    if project.BOARD=="go": return []
    from hdmi_sim import translate
    return translate(OUT)

def elaborate():
    sources=json.loads((OUT/'sources.json').read_text())
    run([FORGE/'bin/hdl/usr/bin/iverilog','-B',FORGE/'bin/hdl/usr/lib/x86_64-linux-gnu/ivl','-g2012','-s',TARGET+'_top','-I','upstream/modules/mcu','-o','elaborate.vvp',*[f for f in sources if f.endswith('.v')],ROOT/'tests/xilinx_sim.v',*simulation_hdmi()],'elaborate.log')
    print(f'Full {EXTENSION} top elaborated')
def ise():
    sys.path.insert(0,str(FORGE/'tools'));import ise_docker
    (OUT/'xst/projnav.tmp').mkdir(parents=True,exist_ok=True)
    (OUT/'ise-completed.json').unlink(missing_ok=True)
    inputs_hash=hashlib.sha256((OUT/'manifest.json').read_bytes()).hexdigest()
    steps=[['xst','-ifn','karabas_go.xst','-ofn','karabas_go.syr'],['ngdbuild','-uc','karabas_go.ucf','-p','xc6slx25-ftg256-2','karabas_go.ngc','karabas_go.ngd'],['map','-p','xc6slx25-ftg256-2','-w','-o','karabas_go_map.ncd','karabas_go.ngd','karabas_go.pcf'],['par','-w','karabas_go_map.ncd',f'{TARGET}.ncd','karabas_go.pcf'],['trce','-v','20','-u','20',f'{TARGET}.ncd','-o',f'{TARGET}.twr','karabas_go.pcf']]
    steps=[[s.replace('karabas_go',TARGET) for s in cmd] for cmd in steps]
    for cmd in steps:
        print('Running '+cmd[0],flush=True);run(ise_docker.command(cmd,workdir=OUT,build_root=ROOT/'build'),cmd[0]+'.log')
    if 'All constraints were met' not in (OUT/f'{TARGET}.twr').read_text():raise RuntimeError('Timing failed; package blocked')
    run(ise_docker.command(['bitgen','-f',f'{TARGET}.ut',f'{TARGET}.ncd'],workdir=OUT,build_root=ROOT/'build'),'bitgen.log')
    if inputs_hash!=hashlib.sha256((OUT/'manifest.json').read_bytes()).hexdigest():raise RuntimeError('Inputs changed during ISE')
    (OUT/'ise-completed.json').write_text(json.dumps({'manifest_sha256':hashlib.sha256((OUT/'manifest.json').read_bytes()).hexdigest(),'bitstream_sha256':hashlib.sha256((OUT/f'{TARGET}.bin').read_bytes()).hexdigest()},indent=2))
def package():
    # Recreate inputs from maintained sources before comparing with routed evidence.
    # Checking the old build directory alone would silently package stale adapters.
    prepare()
    evidence=json.loads((OUT/'ise-completed.json').read_text())
    for key,name in [('manifest_sha256','manifest.json'),('bitstream_sha256',f'{TARGET}.bin')]:
        assert evidence[key]==hashlib.sha256((OUT/name).read_bytes()).hexdigest(),'Stale ISE build'
    for name,digest in json.loads((OUT/'manifest.json').read_text()).items():assert hashlib.sha256((OUT/name).read_bytes()).hexdigest()==digest,name
    if 'All constraints were met' not in (OUT/f'{TARGET}.twr').read_text():raise RuntimeError('Timing failed')
    run([sys.executable,FORGE/'external/karabas-go-tools/make_core/make_core.py','core.json',f'mc0511.{EXTENSION}'])
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--board',choices=['go','mini','minig'],default='go');p.add_argument('command',choices=['prepare','elaborate','ise','package']);a=p.parse_args()
    select_board(a.board);globals()[a.command]()
