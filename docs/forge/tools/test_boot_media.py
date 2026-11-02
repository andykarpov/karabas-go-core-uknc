#!/usr/bin/env python3
"""Capture supplied-media boots through the physical SPI bridge (images read-only).

Screens require review: sectors read and a live CPU alone do not prove program startup.
"""
import argparse,concurrent.futures,hashlib,json,shutil,subprocess,sys
from pathlib import Path
from prepare import ROOT,OUT

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--compiled',action='store_true',help='Use an already completed boot.py compilation')
 p.add_argument('--jobs',type=int,default=3)
 p.add_argument('--run-ms',type=int,default=12000,help='Time after ROM boot selection')
 p.add_argument('--label',default='media-boots',help='Directory name under build for this run')
 p.add_argument('--cow',action='store_true',help='Allow simulated HDD writes in RAM; supplied files remain read-only')
 p.add_argument('images',nargs='*')
 args=p.parse_args()
 if not args.compiled:subprocess.run([sys.executable,str(ROOT/'tools/boot.py'),'--compile-only'],check=True)
 if Path(args.label).name!=args.label or args.label in ('.','..'):p.error('label must be a directory name')
 dest=ROOT/'build'/args.label;dest.mkdir(parents=True,exist_ok=True)
 executable=dest/'boot';shutil.copyfile(OUT/'boot_obj/boot',executable);executable.chmod(0o755)
 images=args.images or [x.name for x in sorted((ROOT/'res/media').iterdir()) if x.suffix.lower()=='.dsk']+['WDC170inv_P.img']
 def boot(name):
  path=ROOT/'res/media'/name
  if path.parent!=ROOT/'res/media' or not path.is_file():raise ValueError(name)
  key=path.stem;log=dest/(key+'.log');frame=dest/(key+'.ppm')
  command=[str(executable),f'+FRAME={frame}',f'+RUN_MS={args.run_ms}']
  if args.cow:command+=['+COW']
  if path.suffix.lower()=='.dsk':command+=[f'+DSK={path}']
  else:command+=[f'+HDD={path}','+KEY=27','+KEY_AFTER_MS=2000'] # WDROM partition 0, Enter
  with log.open('w') as f:result=subprocess.run(command,cwd=OUT,stdout=f,stderr=subprocess.STDOUT)
  text=log.read_text()
  passed=result.returncode==0 and 'errors=0' in text and frame.is_file()
  record=dict(image=name,image_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),command=command,
              transport_and_memory_pass=passed,screen_review='pending',log=str(log),frame=str(frame))
  print(name+': '+('captured; review screen' if passed else 'FAILED'),flush=True)
  return record
 with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:records=list(pool.map(boot,images))
 (dest/'results.json').write_text(json.dumps(dict(binary_sha256=hashlib.sha256(executable.read_bytes()).hexdigest(),results=records),indent=2)+'\n')
 if not all(x['transport_and_memory_pass'] for x in records):raise SystemExit(1)

if __name__=='__main__':main()
