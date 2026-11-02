"""Translate the real VHDL transmitter; vendor clock models stay under build/."""
import os,re,subprocess,sys,tarfile
from prepare import ROOT,FORGE,MOD

def translate(out):
    work=out/'hdmi-sim'; work.mkdir(exist_ok=True)
    for n in ('w93','w08'): (work/n).mkdir(exist_ok=True)
    hdmi=out/'upstream/modules/video/hdmi'
    env=os.environ.copy(); hdl=FORGE/'bin/hdl/usr'
    env['LD_LIBRARY_PATH']=str(hdl/'lib/x86_64-linux-gnu')
    env['GHDL_PREFIX']=str(hdl/'lib/ghdl/mcode/vhdl')
    ghdl=hdl/'bin/ghdl-mcode'
    def run(args,stdout=None):
        r=subprocess.run(list(map(str,args)),cwd=work,env=env,text=True,capture_output=True)
        (work/'translation.log').open('a').write(r.stderr)
        if r.returncode: raise RuntimeError(r.stderr[-6000:])
        if stdout: (work/stdout).write_text(r.stdout)
    tx=(hdmi/'zhdmi_tx.vhd').read_text().replace('architecture rtl of hdmi_tx is\n','''architecture rtl of hdmi_tx is
 component dvi port (CLK, RESET : in std_logic; RGB : in std_logic_vector(23 downto 0);
 HSYNC, VSYNC, DE : in std_logic; ENC_RED, ENC_GREEN, ENC_BLUE : out std_logic_vector(9 downto 0));
 end component;
''').replace('dvi: entity work.dvi port map(', 'dvi_inst: dvi port map(')
    (work/'tx.vhd').write_text(tx)
    run([ghdl,'-a','--std=93c','--workdir=w93','--work=unisim',MOD.parent/'sim/lint/unisim_stubs.vhd'])
    names=['zhdmi_tmds_encoder','zhdmi_tmds_serializer_spartan6','zhdmi_audio_packetizer','zhdmi_island_encoder','zhdmi_packet_gen','zhdmi_signaling']
    run([ghdl,'--synth','--std=93c','--ieee=synopsys','--workdir=w93','-Pw93','--out=verilog','-gSAMPLE_FREQ=48000',*[hdmi/(n+'.vhd') for n in names],'tx.vhd','-e','hdmi_tx'],'hdmi_tx.v')
    path=work/'hdmi_tx.v';t=path.read_text()
    t,n=re.subn(r'(module hdmi_tx\b.*?\);)',r'\1\nparameter SAMPLE_FREQ=48000;',t,count=1,flags=re.S)
    assert n==1;path.write_text(t)
    run([ghdl,'--synth','--std=08','--ieee=synopsys','--workdir=w08','--out=verilog',hdmi/'dvi_encoder.vhd',hdmi/'dvi.vhd','-e','dvi'],'dvi.v')
    models=ROOT/'build/hdmi-vendor-models'
    if not (models/'glbl.v').exists():
        models.mkdir(exist_ok=True)
        sys.path.insert(0,str(FORGE/'tools'));import ise_docker
        archive=models/'models.tar'
        run(ise_docker.command(['tar','cf','/build/hdmi-vendor-models/models.tar','-C','/opt/Xilinx/14.7/ISE_DS/ISE/verilog/src','unisims','glbl.v'],workdir=out,build_root=ROOT/'build'))
        with tarfile.open(archive) as stream:stream.extractall(models,filter='data')
        for p in (models/'unisims').glob('*.v'):
            p.write_text('`default_nettype wire\n'+p.read_text())
    return [str(work/'hdmi_tx.v'),str(work/'dvi.v'),'-y',str(models/'unisims'),'-s','glbl',str(models/'glbl.v')]
