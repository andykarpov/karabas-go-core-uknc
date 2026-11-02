#!/usr/bin/env python3
"""Verify all board bundles and archive firmware, supplied media and instructions."""
import hashlib,json,struct,zipfile
from pathlib import Path
from prepare import ROOT,verify_inputs
from port_boards import BOARDS

def require(ok,message):
    if not ok:raise RuntimeError(message)

def package(data,config,bitstream):
    require(data[:4]==b'kgo1','Core signature')
    for start,end,field in [(4,36,'id'),(36,68,'name'),(68,76,'build')]:
        require(data[start:end].decode('ascii').rstrip()==config[field],f'Core {field}')
    size=int.from_bytes(data[80:84],'big')
    require(int.from_bytes(data[84:88],'big')==0 and not config['roms'],'Unexpected external ROM payload')
    require(data[1024:1024+size]==bitstream,'FPGA payload differs from timing-accepted build')
    require(data[185]==16,'SPI clock setting')
    pos=1024+size
    require(data[pos]==len(config['osd']),'OSD length');pos+=1
    types={'S':0,'N':1,'T':2,'H':3,'P':4,'F':5,'FL':6}
    for index,item in enumerate(config['osd']):
        require(data[pos]==types[item['type']],'OSD type')
        require(data[pos+2:pos+18].decode('ascii').rstrip()==item['name'][:16].rstrip(),'OSD name')
        require(data[pos+18]==data[512+index]==item.get('default',0),'OSD default')
        count=data[pos+19];pos+=20
        if item['type'] in ('F','FL'):
            require(count==item.get('slot',0)|(128 if item.get('autoload') else 0),'Media slot')
            require(data[pos:pos+256].decode('ascii').rstrip()==item['extensions'],'Media extensions')
            require(data[pos+256:pos+512].rstrip(b'\0').decode('ascii')==item['dir'],'Media directory')
            require(data[pos+512:pos+768].rstrip(b'\0').decode('ascii')==item.get('filename',''),'Media filename')
            pos+=768
        else:
            choices=[data[pos+i*16:pos+(i+1)*16].decode('ascii').rstrip() for i in range(count)]
            require(choices==item.get('options',[]),'OSD choices');pos+=16*count
        expected=item['name'].ljust(32)[16:32] if item['type']=='P' else item.get('hotkey','').ljust(16)
        require(data[pos:pos+16].decode('ascii')==expected,'OSD hotkey/text')
        pos+=21
    require(pos==len(data),'Truncated or trailing core data')

def uf2(data):
    require(len(data)%512==0,'UF2 size')
    count=len(data)//512;addresses=set()
    for i in range(count):
        block=data[i*512:(i+1)*512]
        magic1,magic2,flags,address,size,num,total,family=struct.unpack('<8I',block[:32])
        require((magic1,magic2)==(0x0a324655,0x9e5d5157),'UF2 start magic')
        require(struct.unpack('<I',block[-4:])[0]==0x0ab16f30,'UF2 end magic')
        require(flags&0x2000 and family==0xe48bff56,'UF2 is not RP2040')
        require(size==256 and num==i and total==count,'UF2 block ordering/size')
        require(0x10000000<=address and address+size<=0x11000000 and address%256==0,'UF2 flash address')
        require(address not in addresses,'Duplicate UF2 block');addresses.add(address)

def main():
    verify_inputs()
    entries={};builds=set()
    for board,ext in BOARDS.items():
        folder=ROOT/'bin'/ext;out=ROOT/'build'/ext
        manifest=json.loads((folder/'manifest.json').read_text());builds.add(manifest['build'])
        evidence=json.loads((out/'ise-completed.json').read_text())
        require(manifest['fpga']==evidence,f'{board}: provenance differs')
        require(hashlib.sha256((out/'manifest.json').read_bytes()).hexdigest()==evidence['manifest_sha256'],f'{board}: source manifest')
        for name,digest in json.loads((out/'manifest.json').read_text()).items():
            require(hashlib.sha256((out/name).read_bytes()).hexdigest()==digest,f'{board}: input changed: {name}')
        require('All constraints were met' in (out/f'karabas_{board}.twr').read_text(),f'{board}: timing')
        bitstream=(out/f'karabas_{board}.bin').read_bytes()
        require(hashlib.sha256(bitstream).hexdigest()==evidence['bitstream_sha256'],f'{board}: bitstream')
        for name,info in manifest['files'].items():
            path=folder/name;data=path.read_bytes()
            require(len(data)==info['bytes'] and hashlib.sha256(data).hexdigest()==info['sha256'],f'{board}: checksum {name}')
            if name.endswith('.uf2'):uf2(data)
            else:package(data,json.loads((out/'core.json').read_text()),bitstream)
            entries[f'{ext}/{name}']=path
        entries[f'{ext}/manifest.json']=folder/'manifest.json'
        entries[f'validation/{ext}-timing.txt']=out/f'karabas_{board}.twr'
        entries[f'validation/{ext}-core.json']=out/'core.json'
        print(f'PASS {board}: core header, FPGA payload, every menu entry, RP2040 UF2 blocks and hashes',flush=True)
    require(len(builds)==1,'Different core builds')
    build=builds.pop()
    for path in sorted((ROOT/'res/media').rglob('*')):
        if path.is_file():entries['mc0511-media/'+str(path.relative_to(ROOT/'res/media'))]=path
    entries['README.md']=ROOT/'docs/builds-and-installation.md'
    for name in ('validation.md','hdd-performance.md','attribution.md'):entries[name]=ROOT/'docs'/name
    entries['sources.lock.json']=ROOT/'config/sources.lock.json'
    checksums=''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {name}\n' for name,path in entries.items())
    archive=ROOT/'bin'/f'mc0511-{build}-all.zip'
    temporary=archive.with_suffix('.zip.tmp')
    with zipfile.ZipFile(temporary,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for name,path in entries.items():z.write(path,name)
        z.writestr('SHA256SUMS',checksums)
    # Read back every member, validating ZIP CRC and content hashes before publishing.
    with zipfile.ZipFile(temporary) as z:
        for line in checksums.splitlines():
            digest,name=line.split('  ',1)
            require(hashlib.sha256(z.read(name)).hexdigest()==digest,f'Archive verification: {name}')
    temporary.replace(archive)
    digest=hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n')
    print(f'Created and verified {archive} ({archive.stat().st_size:,} bytes)\nSHA256 {digest}')

if __name__=='__main__':main()
