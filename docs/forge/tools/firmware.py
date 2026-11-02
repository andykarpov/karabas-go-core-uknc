#!/usr/bin/env python3
"""Reproducible core-owned Karabas firmware overlay; never edit shared references."""
from pathlib import Path
import re,shutil,sys,os,json,hashlib,subprocess,argparse
from prepare import ROOT,FORGE,TANG,replace
SRC=FORGE/'external/karabas-go-firmware';DST=ROOT/'build/firmware'
def edit(name,fn):
 p=DST/name;p.write_text(fn(p.read_text()))
def prepare(profile_storage=False):
 shutil.copytree(SRC,DST,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.git','.pio','build'))
 for src in (ROOT/'firmware').glob('*'):
  if src.suffix in ('.h','.cpp','.inc'):shutil.copyfile(src,DST/'src'/src.name)
 # Preserve the volume algorithm as C, sharing it with host regression tests.
 text=(TANG/'mnano/rt11sav.c').read_text().split('// The host build:')[0]
 text=text[:text.rfind('// ---------------------------------------------------------------------')]
 a=text.index('typedef struct {');b=text.index('} rt11_io_t;',a)+len('} rt11_io_t;')
 typedef=text[a:b];text=text[:a]+text[b:]
 text=text.replace('#include "rt11sav.h"','#include "rt11_volume.h"').replace('static int rt11_build(', 'int rt11_build(')
 (DST/'src/rt11_volume.c').write_text(text)
 (DST/'src/rt11_volume.h').write_text('#pragma once\n#include <stdint.h>\n#ifdef __cplusplus\nextern "C" {\n#endif\n'+typedef+'\nunsigned rt11sav_date(int,int,int);\nint rt11_build(const rt11_io_t*,const char*,unsigned,unsigned,int (*)(void*,uint8_t*),void*,char*,const char**);\n#ifdef __cplusplus\n}\n#endif\n')
 edit('src/config.h',lambda s:s.replace('#define MAX_OSD_ITEMS 32','#define MAX_OSD_ITEMS 64'))
 edit('src/types.h',lambda s:s.replace('core_osd_option_t options[MAX_OSD_ITEM_OPTIONS];','core_osd_option_t *options; // bounded pool, allocated while reading core'))
 def loader(s):
  s='#include "mc0511.h"\n'+s
  s=s.replace('core_item_t core;', 'core_item_t core;\nstatic core_osd_option_t option_pool[512];\nstatic unsigned option_used=0;')
  s=s.replace('file_seek(offset); core.osd_len = file_read();','file_seek(offset); core.osd_len = file_read();\n  if(core.osd_len>MAX_OSD_ITEMS) halt("Too many OSD items");\n  option_used=0;')
  s=s.replace('core.osd[i].type = file_read();','core.osd[i].options=nullptr;\n    core.osd[i].type = file_read();')
  s=replace(s,'''if (core.osd[i].options_len > 8) {
        core.osd[i].options_len = 8; // something goes wrong
      }''','''if (option_used+core.osd[i].options_len>512) halt("Too many OSD choices");
      core.osd[i].options=option_pool+option_used;
      option_used+=core.osd[i].options_len;''')
  s=s.replace('void core_ioctl_send(uint8_t slot, bool popup)\n{','void core_ioctl_send(uint8_t slot, bool popup)\n{\n  if(mc0511_active() && slot==5) {mc0511_run_sav();return;}')
  s=s.replace('core_send_all();','core_send_all();\n  mc0511_rtc_seed();')
  s=s.replace('file_slots[core.osd[i].slot_id].is_autoload =','if(core.osd[i].slot_id>=MAX_FILE_SLOTS) halt("Invalid image slot");\n      file_slots[core.osd[i].slot_id].is_autoload =')
  return s
 edit('src/fpga/core_loader.cpp',loader)
 def mount(s):
  s='#include "mc0511.h"\n'+s
  s=s.replace('core_file_slot_t &fs = file_slots[slot];','mc0511_sanitize_slot(slot);\n  core_file_slot_t &fs = file_slots[slot];')
  s=s.replace('void img_register_handlers() {','void img_register_handlers() {\n  mc0511_register_handlers();')
  s=s.replace('matrix_drive_mount(slot, (uint32_t)', 'mc0511_geometry(slot);\n  matrix_drive_mount(slot, (uint32_t)')
  return s
 edit('src/storage/img_mount.cpp',mount)
 from port_ui import adapt_input, adapt_osd_header, adapt_osd
 edit('src/input/input.cpp',adapt_input)
 edit('lib/OSD/OSD.h',adapt_osd_header)
 edit('lib/OSD/OSD.cpp',adapt_osd)
 if profile_storage:
  from port_storage import adapt as adapt_storage, adapt_link, adapt_serial
  shutil.copyfile(ROOT/'tools/profiles/hdd_profile.h',DST/'src/hdd_profile.h')
  edit('src/storage/img_mount.cpp',adapt_storage)
  edit('src/fpga/link.cpp',adapt_link)
  edit('src/periph/serial_bridge.cpp',adapt_serial)
  edit('src/periph/oled.cpp',lambda s:replace(s,'#include "main.h"','#include "main.h"\n#include "hdd_profile.h"').replace(
    '  if (!has_oled) return;', '  if (!has_oled || hdd_profile.pause_oled) return;'))
  # A diagnostic session starts in the chooser; do not change saved settings.
  edit('src/app_core_browser.cpp',lambda s:replace(s,'void app_core_browser_on_time() {',
    'void app_core_browser_on_time() {\n  return; // HDD timing build: select the test core manually'))
 else:
  (DST/'src/hdd_profile.h').unlink(missing_ok=True)
  from port_performance import adapt_link, adapt_link_header, adapt_storage, adapt_oled
  from port_performance import adapt_sega_header, adapt_sega, adapt_go_board
  edit('src/fpga/link.cpp',adapt_link)
  edit('src/fpga/link.h',adapt_link_header)
  edit('src/storage/img_mount.cpp',adapt_storage)
  edit('src/periph/oled.cpp',adapt_oled)
  edit('lib/SegaController/SegaController.h',adapt_sega_header)
  edit('lib/SegaController/SegaController.cpp',adapt_sega)
  edit('src/board/board_go.cpp',adapt_go_board)
 # DEDICATED_SPI may leave CMD18 active after browsing or reading an image.
 # End the card transaction before MCU-only resets; the SD remains powered.
 edit('src/storage/msc.cpp',lambda s:replace(s,'  bk_flush();\n  matrix_icon(MATRIX_ICON_MSC);',
  '  bk_flush();\n  if (has_sd && !sd1.card()->syncDevice()) { d_println("MSC: SD1 sync failed; not rebooting"); return; }\n  matrix_icon(MATRIX_ICON_MSC);'))
 edit('src/periph/serial_bridge.cpp',lambda s:replace(s,'    bk_flush();\n    Serial.print("OK\\r\\n");',
  '    bk_flush();\n    if (has_sd && !sd1.card()->syncDevice()) { Serial.print("ERROR\\r\\n"); return; }\n    Serial.print("OK\\r\\n");'))
 def ui(s):
  s='#include "main.h"\n#include "mc0511.h"\n'+s
  s=replace(s,'void app_core_overlay(bool force)\n{','''void app_core_overlay(bool force)
{
  const bool mc_frame = mc0511_active();
  if (mc_frame) zxosd.beginFrame();''')
  s=replace(s,'  zxosd.update();\n}\n\nvoid app_core_menu(uint8_t vpos) {',
    '  if (mc_frame) zxosd.endFrame();\n  zxosd.update();\n}\n\nvoid app_core_menu(uint8_t vpos) {')
  # Include after filebrowser_open/eject definitions, before menu navigation.
  s=s.replace('uint8_t find_first_item() {','#include "mc0511_ui.inc"\n\nuint8_t find_first_item() {')
  s=s.replace('void app_core_menu(uint8_t vpos) {','void app_core_menu(uint8_t vpos) {\n  if(mc0511_active()){mc_menu_draw(vpos);return;}')
  s=s.replace('curr_osd_item = find_first_item();','curr_osd_item = find_first_item();\n    if(mc0511_active())mc_menu_reset();')
  s=s.replace('void app_core_on_keyboard() {','''void app_core_on_keyboard() {
  if(mc0511_active() && !is_filebrowser) {
    mc_menu_key();
    if(osd_state!=state_main)return;
    if(is_filebrowser){filebrowser_slot=app_core_init_filebrowser();app_core_filebrowser(APP_COREBROWSER_MENU_OFFSET);}
    else app_core_overlay(false);
    if(core.osd_need_save)app_core_save(curr_osd_item);
    zxosd.update();return;
  }''')
  s=s.replace('if (core_osd_can_phys(curr_osd_item))', 'if (!mc0511_active() && core_osd_can_phys(curr_osd_item))')
  s=s.replace('// working dir\n', '// working dir\n  mc0511_sanitize_slot(core.osd[curr_osd_item].slot_id);\n')
  s=s.replace('if (dir.length() > 1)', 'if (dir.length() > 1 && (!mc0511_active() || dir != MC0511_MEDIA))')
  # Root jump is localized to this application (the core chooser is unaffected).
  s=s.replace('String dir = "/";', 'String dir = mc0511_active()?MC0511_MEDIA:"/";')
  s=s.replace('strcpy(file_slots[core.osd[curr_osd_item].slot_id].dir, "/");','strcpy(file_slots[core.osd[curr_osd_item].slot_id].dir, mc0511_active()?MC0511_MEDIA:"/");')
  s=s.replace('uint16_t id;\n    item', '''if(mc0511_active() && !file1.isDir() && !kg_name_has_ext(filename,file_slots[core.osd[curr_osd_item].slot_id].ext)) {file1.close();continue;}
    uint16_t id;
    item''')
  # Header/text items have no allocated options (also true of old-style generic cores).
  s=s.replace('option = String(core.osd[i].options[core.osd[i].val].name);','option = core.osd[i].options_len ? String(core.osd[i].options[core.osd[i].val].name) : String("");')
  return s
 edit('src/app_core.cpp',ui)
 edit('src/ui/osd_ui.cpp',lambda s:'#include \"mc0511.h\"\n'+s.replace('app_core_on_keyboard },', 'app_core_on_keyboard, mc0511_ui_tick },'))
 print(DST)
def source_hashes():
 return {str(p.relative_to(DST)):hashlib.sha256(p.read_bytes()).hexdigest()
         for p in sorted(DST.rglob('*')) if p.is_file() and '.pio' not in p.parts
         and p.suffix in ('.cpp','.c','.h','.inc','.ini','.py')}
def build(profile_storage=False,board="go"):
 if board not in ("go","mini","minig"): raise ValueError(board)
 prepare(profile_storage=profile_storage)
 executable=ROOT/'build/venv/bin/platformio'
 if not executable.exists():
  found=shutil.which('platformio') or shutil.which('pio')
  if not found:raise RuntimeError('Install PlatformIO in build/venv as described in README.md')
  executable=Path(found)
 before=source_hashes()
 env=os.environ.copy();env['PLATFORMIO_CORE_DIR']=str(ROOT/'build/platformio')
 logpath=ROOT/'build'/('firmware-build.log' if board=='go' else f'firmware-{board}-build.log')
 with logpath.open('w') as log:
  result=subprocess.run([str(executable),'run','-d',str(DST),'-e',board],env=env,stdout=log,stderr=subprocess.STDOUT)
 if result.returncode:
  print(logpath.read_text()[-6000:]);result.check_returncode()
 if before!=source_hashes():raise RuntimeError('Firmware source changed during build')
 uf2=DST/f'.pio/build/{board}/firmware.uf2'
 (ROOT/'build'/('firmware-completed.json' if board=='go' else f'firmware-{board}-completed.json')).write_text(json.dumps(dict(sources=before,uf2_sha256=hashlib.sha256(uf2.read_bytes()).hexdigest()),indent=2)+'\n')
 print('Firmware built and source hashes recorded:',uf2)
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('command',nargs='?',default='prepare',choices=['prepare','build'])
 parser.add_argument('--profile-storage',action='store_true',help='Diagnostic build with SD/FPGA read timing counters; not a release bundle')
 parser.add_argument('--board',choices=['go','mini','minig'],default='go')
 args=parser.parse_args()
 if args.command=='build': build(profile_storage=args.profile_storage,board=args.board)
 else: prepare(profile_storage=args.profile_storage)

