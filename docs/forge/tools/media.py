#!/usr/bin/env python3
"""Stage every supplied resource below SD1/mc0511-media and verify file hashes."""
import argparse,hashlib,json,shutil,os
from pathlib import Path
from prepare import ROOT

def stage(destination):
    destination=destination.resolve();out=destination/'mc0511-media';out.mkdir(parents=True,exist_ok=True)
    records=[]
    for src in sorted((ROOT/'res/media').rglob('*')):
        if not src.is_file():continue
        rel=src.relative_to(ROOT/'res/media');dst=out/rel;dst.parent.mkdir(parents=True,exist_ok=True)
        digest=hashlib.sha256(src.read_bytes()).hexdigest()
        if dst.exists() and hashlib.sha256(dst.read_bytes()).hexdigest()!=digest:raise RuntimeError(f'Refusing to replace different media: {dst}')
        if not dst.exists():
            print(f'Copying {rel}',flush=True)
            shutil.copy2(src,dst)
        # Hashing page-cache data is not a flush. Do not report success while
        # a large USB-card write is still pending in the kernel.
        with dst.open('rb') as stream:os.fsync(stream.fileno())
        assert hashlib.sha256(dst.read_bytes()).hexdigest()==digest
        records.append(dict(path='mc0511-media/'+str(rel),bytes=src.stat().st_size,sha256=digest))
    for folder in [*sorted((p for p in out.rglob('*') if p.is_dir()),reverse=True),out,destination]:
        fd=os.open(folder,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(fd)
        finally:os.close(fd)
    evidence=ROOT/'build/media-manifest.json';evidence.write_text(json.dumps(records,indent=2)+'\n')
    print(f'{len(records)} files synced and hash-verified in {out}; unmount/eject SD1 before disconnecting')
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--sd1-root',type=Path,default=ROOT/'build/sd1');args=p.parse_args();stage(args.sd1_root)
