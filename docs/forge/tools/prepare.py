#!/usr/bin/env python3
"""Prepare the KG1 port without modifying the reference repositories."""
from pathlib import Path
import hashlib, json, re, shutil, subprocess, sys, xml.etree.ElementTree as ET
sys.dont_write_bytecode = True  # importing reference helpers must not write into external/
ROOT = Path(__file__).resolve().parents[1]
FORGE = next(p for p in ROOT.parents if (p/'config/forge.json').exists())
TANG = FORGE/'external/tang-uknc'
MOD = FORGE/'external/karabas-go-core-tsconf/modules/rtl'
TS = FORGE/'external/karabas-go-core-tsconf/src'
OUT = ROOT/'build/kg1'
BOARD = 'go'
TARGET = 'karabas_go'
EXTENSION = 'kg1'

def select_board(board):
    global OUT, BOARD, TARGET, EXTENSION
    from port_boards import BOARDS
    BOARD=board; TARGET='karabas_'+board; EXTENSION=BOARDS[board]
    OUT=ROOT/'build'/EXTENSION

def replace(s, old, new):
    if s.count(old) != 1: raise ValueError(f'Expected one occurrence: {old[:80]}')
    return s.replace(old,new)

def machine():
    s = (TANG/'tang/src/top.v').read_text()
    s = s[s.index('//------------------------------------------------------------//\n// RAM cpu/ppu'):]
    # Memory and machine bus/device wiring are retained; replace Tang's host and display.
    a = s.index('//------------------------------------------------------------//\n//  HDMI/LCD')
    b = s.index('//------------------------------------------------------------//\n//  Wishbone PPU')
    s = s[:a] + (ROOT/'src/rtl/host.inc').read_text().replace('// SWITCHES_INCLUDE',(ROOT/'src/rtl/switches.inc').read_text()) + '\n' + s[b:]
    s = s.replace('(           clk_25),', '(       clk_25_raw),', 1).replace('(         clk_3_12),', '(     clk_3_12_raw),', 1)
    s = s.replace('(           locked)', '(   memory_aligned)')
    s = s.replace('wire pp_rst = system_reset[0] | ~init;', 'wire pp_rst = system_reset[0] | host_busy | ~init;')
    s = s.replace('.hdd_present(mount_dsk[4] & system_hdd_en),', '.hdd_present(mount_dsk[4] & system_hdd_en),\n    .image_sectors(hdd_sectors),')
    s = s.replace('assign leds[1] = ~sound;', 'assign beeper = sound & system_beeper;')
    s = re.sub(r'assign leds\[[^;]+;', '', s)
    s = s.replace('.led_init     (      leds[5])', '.led_init     (             )')
    s = s.replace('assign hdmi_audio_l = volume_data_l;', 'assign audio_l = volume_data_l;')
    s = s.replace('assign hdmi_audio_r = volume_data_r;', 'assign audio_r = volume_data_r;')
    s = s.replace('assign uart_tx = cl_active ? cl_tx : vp65_uart_tx;', 'assign uart_tx = vp65_uart_tx;')
    s = s.replace('.rst_n     (   sys_rst)', '.rst_n     (       init)')
    # Retain the image controller and its PPU ACK timing. Only the selected
    # physical slot uses the cable data path; it must never request SD sectors.
    a=s.index('fdd4 fdd(');b=s.index('\n);',a)+3
    fdd=s[a:b]
    fdd=replace(fdd,'.motor        (   disk_motor)', '.motor        (disk_motor && !physical_selected && system_fdd_en)')
    fdd=replace(fdd,'.step         (    disk_step)', '.step         (disk_step && !physical_selected && system_fdd_en)')
    fdd=replace(fdd,'.write        (   disk_write)', '.write        (disk_write && !physical_selected && system_fdd_en)')
    fdd=replace(fdd,'.rstart       (       fdd_rd)', '.rstart       ( image_fdd_rd)')
    fdd=replace(fdd,'.wstart       (       fdd_wr)', '.wstart       ( image_fdd_wr)')
    s=s[:a]+(ROOT/'src/rtl/physical_fdd.inc').read_text()+'\n'+fdd+s[b:]
    s=replace(s,'.ppu_wbm_dat_o(ppu_wbm_dat_i_128)', '.ppu_wbm_dat_o(virtual_fdd_data)')
    decls=re.findall(r'^(?:wire|reg)[^;]*;',s,re.M)
    s=re.sub(r'^(?:wire|reg)[^;]*;', '',s,flags=re.M)
    return (ROOT/'src/rtl/machine_header.inc').read_text() + '\n'.join(decls) + '\n' + s

def verify_inputs():
    for repo in json.loads((ROOT/'config/sources.lock.json').read_text())['repositories']:
        actual=subprocess.check_output(['git','-C',str(FORGE/repo['path']),'rev-parse','HEAD'],text=True).strip()
        if actual!=repo['revision']:raise RuntimeError('Source revision changed: '+repo['path'])
    for item in json.loads((ROOT/'res/manifest.json').read_text())['resources']:
        p=ROOT/item['path']
        if p.stat().st_size!=item['bytes'] or hashlib.sha256(p.read_bytes()).hexdigest()!=item['sha256']:
            raise RuntimeError('Media changed: '+str(p))

def main():
    verify_inputs()
    OUT.mkdir(parents=True,exist_ok=True)
    files=[]
    def put(src,rel):
        dst=OUT/rel; dst.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(src,dst)
        if src.name=='kg_osd_overlay.v':
            from port_osd import adapt
            dst.write_text(adapt(dst.read_text()))
        if src.name=='ide.v':
            from port_ide import adapt
            dst.write_text(adapt(dst.read_text()))
        if src.name=='audio.v':
            # I2S WS changes one bit BEFORE the MSB. Source emits its MSB
            # at counts 3/19; changing WS there loses bit 15 at an I2S DAC.
            t=dst.read_text().replace("(b_cnt == 5'd3)?1'b0: ((b_cnt == 5'd19)?1'b1", "(b_cnt == 5'd2)?1'b0: ((b_cnt == 5'd18)?1'b1")
            if t==dst.read_text():raise RuntimeError('Audio serializer phase patch did not match')
            dst.write_text(t)
        if src.name=='kakave.v':
            t=dst.read_text().replace("25'd21937500","25'd21875000")
            t=t.replace("3'd4: begin min","3'd5: begin sec <= (set_val > 59) ? 0 : set_val[5:0]; frac <= 0; end\n        3'd4: begin min")
            dst.write_text(t)
        if src.name=='fdd4.v':
            t=dst.read_text()
            t=t.replace('reg  read_sd  =', """// The RP2040 may service a sector after the original 1.3 ms gap.
// Hold rotation in the header/data gap until the checked sector arrives.
// Never expose stale buffer words as a sector with a good synthetic CRC.
reg sector_ready=0;
reg [31:0] requested_sector=0;
reg [1:0] requested_drive=0;
always @(posedge pin_25mhz_ck)begin
 if(read_sd && !rbusy)begin requested_sector<=sd_sec;requested_drive<=drive;end
 if(!motor || step_r || head_old!=head || drive_old!=drive || ppu_vm_init_i || word_sectr==0)
  sector_ready<=0;
 else if(outen && outaddr==511)
  sector_ready<=(requested_sector==sd_sec && requested_drive==drive);
end
reg  read_sd  =""")
            t=t.replace("count_clk <= count_clk==1599 ? 11'd0 : count_clk + 1'b1;", "if(!(disk_insert && word_sectr==9'h1C && count_clk==1598 && !sector_ready))\n        count_clk <= count_clk==1599 ? 11'd0 : count_clk + 1'b1;")
            t=t.replace('else if(sd_rd && !sd_rd_d) read_sd <= disk_insert;', 'else read_sd <= sd_rd && disk_insert && !sector_ready;')
            dst.write_text(t)
        if src.name=='xm2-01.v':
            t=dst.read_text().replace('always @(posedge timer_clk)begin', "reg timer_old=0;\nalways @(posedge pin_vm_clk25)begin\n timer_old<=timer_clk;\n if(timer_clk && !timer_old)begin")
            t=t.replace('end\n//========================================================================================\nendmodule', 'end\nend\n//========================================================================================\nendmodule')
            dst.write_text(t)
        if src.name=='sdram2.v':
            t=dst.read_text()
            t=t.replace('horz <= 0;', "horz <= 11'd8;")
            t=t.replace("reg  [15:0] SDRAM_DQ = 16'hZZZZ;", "reg [15:0] SDRAM_DQ=0;\nreg SDRAM_oe=0;")
            t=t.replace('assign SDRAM_DQr = SDRAM_DQ;', "assign SDRAM_DQr = SDRAM_oe ? SDRAM_DQ : 16'hzzzz;")
            def drive(m):
                expr=m[1]
                if 'ZZZZ' in expr:return 'SDRAM_oe <= 0;'
                return 'begin SDRAM_DQ <= '+expr+'; SDRAM_oe <= 1; end'
            t=re.sub(r'SDRAM_DQ\s*<=\s*([^;]+);',drive,t)
            # GO has an external 8192-row SDRAM: five refreshes per 32 us line.
            # These idle video slots each reserve 320 ns (> tRFC); no false timing paths.
            t=t.replace('wire refresh  = xx == 83;', 'wire refresh = xx >= 83 && xx <= 87;')
            from port_sdram import retime
            t=retime(t)
            dst.write_text(t)
        if dst.suffix == '.sv':
            text=dst.read_text().replace('always_comb','always @*').replace('ymreg[16]','ymreg[0:15]')
            text=text.replace("ymreg     <= '{default:0};", "for(integer k=0;k<16;k=k+1) ymreg[k] <= 8'd0;")
            text=text.replace("ymreg[7]  <= '1;", "ymreg[7] <= 8'hff;").replace("addr      <= '0;", "addr <= 8'd0;")
            text=text.replace("tone_cnt  <= '{default:0};", "for(integer k=0;k<3;k=k+1) tone_cnt[k] <= 0;")
            pattern=r"wire \[7:0\] volTable\[64\] = '\{(.*?)\};"
            match=re.search(pattern,text,re.S)
            if match:
                vals=re.findall(r"8'h[0-9a-fA-F]+",match[1])
                text=text[:match.start()]+"wire [7:0] volTable[0:63];\n"+''.join(f"assign volTable[{i}]={v};\n" for i,v in enumerate(vals))+text[match.end():]
            # ISE accepts Verilog-2001, not block-scoped loop declarations.
            text=text.replace('always @(posedge CLK) begin\n\treg', 'always @(posedge CLK) begin : noise_block\n\treg').replace('always @(posedge CLK) begin\n\tinteger', 'always @(posedge CLK) begin : tone_block\n\tinteger')
            text=text.replace('for(integer k=0;', 'for(k=0;').replace('reg [7:0] addr;', 'integer k;\nreg [7:0] addr;')
            counter=iter(range(10))
            text=re.sub(r'begin : noise_block',lambda m:f'begin : local_block_{next(counter)}',text)
            dst.unlink();dst=dst.with_suffix('.v');dst.write_text(text);rel=str(dst.relative_to(OUT))
        if dst.suffix == '.v': files.append(rel)
    required=['aberrant.v','covox.v','mixer.v','kakave.v','audio.v','ay/ym2149.sv','cpu.v','fdd/fdd4.v','ide/ide.v','ide/sd_arbiter.v','mkcolorreg.v','ppu.v','sdram2.v','uart/uart_rx.v','uart/uart_tx.v','vp1-128fdd.v','vp1_120.v','vp65.v','wm2wb/vm2_plm.v','wm2wb/vm2_wb.v','wmrst.v','xm2-01.v']
    active={n.attrib['path'][4:] for n in ET.parse(TANG/'tang/test003.gprj').findall('.//File')}
    for name in required:
        assert name in active,name
        put(TANG/'tang/src'/name,'upstream/tang/'+name)
    for folder in ('mcu','mem','clk','video/osd'):
        for src in sorted((MOD/folder).glob('*')):
            if src.suffix in ('.v','.vh'): put(src,'upstream/modules/'+folder+'/'+src.name)
    for src in sorted((ROOT/'src/rtl').glob('*.v')):
        if src.name=='mc0511_hdmi.v' and BOARD=='go': continue
        if src.name=='karabas_go_top.v' and BOARD!='go':
            from port_boards import top
            rel=f'rtl/{TARGET}_top.v'; (OUT/'rtl').mkdir(exist_ok=True)
            (OUT/rel).write_text(top(src.read_text(),BOARD,(TS/f'rtl/{TARGET}_top.v').read_text()))
            files.append(rel)
        else: put(src,'rtl/'+src.name)
    if BOARD!='go':
        put(MOD/'audio/kg_sigma_delta_dac.v','upstream/modules/audio/kg_sigma_delta_dac.v')
        for line in (TS/'karabas_mini.prj').read_text().splitlines():
            match=re.fullmatch(r'vhdl work "(../modules/rtl/video/hdmi/[^"]+)"',line)
            if match:
                src=TS/match[1]; rel='upstream/modules/video/hdmi/'+src.name
                put(src,rel); files.append(rel)
    machine_text=machine()
    if BOARD!='go':
        from port_boards import machine as mini_machine
        machine_text=mini_machine(machine_text)
    (OUT/'rtl/mc0511_machine.v').write_text(machine_text); files.append('rtl/mc0511_machine.v')
    sys.path.insert(0,str(TANG/'tools'))
    from mif import read_mif
    for name,path,size in [('uknc_rom',TANG/'tang/rom/uknc_rom.mif',16384),('rawtrk',TANG/'tang/src/fdd/rom128/rawtrk.mif',512)]:
        width,depth,mem=read_mif(path)
        mem=list(mem)+[0]*(size-len(mem))
        (OUT/(name+'.hex')).write_text(''.join(f'{v:04x}\n' for v in mem))
    rom=(TANG/'tang/rom/ide_wdromv0110.bin').read_bytes()
    words=[int.from_bytes(rom[i:i+2],'little') for i in range(0,len(rom),2)]
    words += [0]*(16384-len(words))
    (OUT/'ide_wdrom.hex').write_text(''.join(f'{v:04x}\n' for v in words))
    (OUT/f'{TARGET}.prj').write_text(''.join(f'{"vhdl" if f.endswith(".vhd") else "verilog"} work "{f}"\n' for f in files))
    xst=(TS/'karabas_go.xst').read_text()
    (OUT/f'{TARGET}.xst').write_text(xst.replace('karabas_go',TARGET).rstrip()+'\n-vlgincdir {upstream/modules/mcu}\n')
    shutil.copyfile(TS/'karabas_go.ut',OUT/f'{TARGET}.ut')
    pins=(TS/f'{TARGET}.ucf').read_text().split('# Timing constraints.')[0]
    timing=(ROOT/'src/constraints/timing.ucf').read_text()
    if BOARD!='go':
        from port_boards import timing as mini_timing
        timing=mini_timing(timing,BOARD)
        pins=re.sub(r'^NET "FT_CLK" CLOCK_DEDICATED_ROUTE.*\n','',pins,flags=re.M)
    (OUT/f'{TARGET}.ucf').write_text(pins+timing)
    config=json.loads((ROOT/'config/core.json').read_text()); config['bitstream']=f'{TARGET}.bin'
    if BOARD!='go':
        for item in config['osd']:
            if item['name']=='Physical FDD': item['options']=['None']
    (OUT/'core.json').write_text(json.dumps(config,indent=2)+'\n')
    (OUT/'sources.json').write_text(json.dumps(files,indent=2)+'\n')
    manifest={str(p.relative_to(OUT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(OUT.rglob('*')) if p.is_file() and (str(p.relative_to(OUT)) in files or p.suffix in ('.hex','.vh','.ucf','.xst','.prj','.ut'))}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'Prepared {len(files)} HDL files in {OUT}')
if __name__=='__main__': main()
