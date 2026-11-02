// Karabas-rendered submenus. Hidden zero-option records delimit the groups in core.json.
static uint8_t mc_page=0,mc_selected=0,mc_count=0,mc_rows[20];
static bool mc_heading(uint8_t i){return core.osd[i].type==CORE_OSD_TYPE_HIDDEN && core.osd[i].options_len==0;}
static void mc_menu_reset(){mc_page=0;mc_selected=0;}
static void mc_menu_rows(){
 mc_count=0;
 if(mc_page)mc_rows[mc_count++]=255; // Back
 bool main_group=true;
 for(uint8_t i=1;i<core.osd_len && mc_count<20;i++) {
  if(mc_page) {
   if(i<=mc_page)continue;
   if(mc_heading(i))break;
   mc_rows[mc_count++]=i;
  } else {
   if(mc_heading(i)){main_group=false;mc_rows[mc_count++]=i;}
   else if(main_group)mc_rows[mc_count++]=i;
  }
 }
 if(mc_selected>=mc_count)mc_selected=0;
}
static void mc_menu_draw(uint8_t vpos){
 mc_menu_rows();
 zxosd.fill(0,vpos,31,22,' ');
 zxosd.setPos(0,vpos);zxosd.setColor(OSD::COLOR_CYAN_I,OSD::COLOR_BLACK);
 zxosd.print(core.osd[mc_page].name);
 zxosd.setPos(0,21);zxosd.print(mc0511_status_text());
 for(uint8_t row=0;row<mc_count && row<17;row++) {
  uint8_t i=mc_rows[row];
  zxosd.setPos(0,vpos+1+row);
  zxosd.setColor(row==mc_selected?OSD::COLOR_BLACK:OSD::COLOR_WHITE,row==mc_selected?OSD::COLOR_YELLOW_I:OSD::COLOR_BLACK);
  if(i==255){zxosd.print("< Back");continue;}
  auto &item=core.osd[i];
  String name(item.name);name.trim();
  if(item.type==CORE_OSD_TYPE_TEXT){zxosd.print((String(item.name)+item.hotkey).substring(0,32));continue;}
  zxosd.print(name);
  zxosd.setPos(17,vpos+1+row);
  zxosd.setColor(row==mc_selected?OSD::COLOR_BLACK:OSD::COLOR_YELLOW_I,row==mc_selected?OSD::COLOR_YELLOW_I:OSD::COLOR_BLACK);
  if(mc_heading(i)){zxosd.print(">");continue;}
  if(item.type==CORE_OSD_TYPE_FILEMOUNTER || item.type==CORE_OSD_TYPE_FILELOADER) {
   auto &fs=file_slots[item.slot_id];char shortname[16];
   if(fs.filename[0]){kg_short_name(fs.filename,shortname,14);zxosd.print(shortname);}else zxosd.print("-NO IMAGE-");
  } else if(item.options_len && item.val<item.options_len)zxosd.print(item.options[item.val].name);
  else zxosd.print(item.hotkey);
 }
}
static void mc_menu_key(){
 mc_menu_rows();
 uint8_t key=usb_keyboard_report.keycode[0];
 uint16_t joy=joyL|joyR;
 if(key==KEY_S){osd_return_state=state_main;osd_state=state_setup;return;}
 if(key==KEY_A){osd_return_state=state_main;osd_state=state_about;return;}
 if(!mc_count)return;
 if(key==KEY_DOWN || (joy&SC_BTN_DOWN)){mc_selected=(mc_selected+1)%mc_count;return;}
 if(key==KEY_UP || (joy&SC_BTN_UP)){mc_selected=(mc_selected+mc_count-1)%mc_count;return;}
 if(key==KEY_ESC || (mc_page && key==KEY_BACKSPACE) || (joy&UI_JOY_ESC)){mc_menu_reset();return;}
 uint8_t i=mc_rows[mc_selected];
 if(i==255){if(key==KEY_ENTER || key==KEY_LEFT || key==KEY_RIGHT || (joy&(SC_BTN_A|SC_BTN_B)))mc_menu_reset();return;}
 curr_osd_item=i;
 if(key==KEY_DELETE){app_core_eject(i);return;}
 bool left=key==KEY_LEFT || (joy&SC_BTN_LEFT);
 bool select=left || key==KEY_RIGHT || key==KEY_ENTER || (joy&(SC_BTN_RIGHT|SC_BTN_A|SC_BTN_B));
 if(!select)return;
 auto &item=core.osd[i];
 if(mc_heading(i)){mc_page=i;mc_selected=0;return;}
 if(item.type==CORE_OSD_TYPE_FILEMOUNTER || item.type==CORE_OSD_TYPE_FILELOADER){filebrowser_open();return;}
 if(item.type==CORE_OSD_TYPE_TRIGGER){core_trigger(i);return;}
 if(item.options_len){
  item.val=(item.val+item.options_len+(left?-1:1))%item.options_len;
  core_send(i);core.osd_need_save=item.type==CORE_OSD_TYPE_SWITCH;
 }
}

void mc0511_ui_tick(){
 static uint32_t last=0;
 if(!mc0511_active() || is_filebrowser || millis()-last<1000)return;
 last=millis();
 zxosd.beginFrame();
 zxosd.setColor(OSD::COLOR_CYAN_I,OSD::COLOR_BLACK);
 zxosd.fill(0,21,31,21,' ');zxosd.setPos(0,21);zxosd.print(mc0511_status_text());zxosd.endFrame();zxosd.update();
}
