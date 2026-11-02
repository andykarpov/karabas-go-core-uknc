// Execute the maintained menu implementation with a bounded character display.
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
struct String {
 std::string s;
 String(const char *p=""):s(p){} String(std::string p):s(p){}
 void trim(){auto a=s.find_first_not_of(' ');s=a==s.npos?"":s.substr(a,s.find_last_not_of(' ')-a+1);}
 String substring(size_t a,size_t b)const{return s.substr(a,b-a);}
 String operator+(const char *p)const{return s+p;}
};
enum {CORE_OSD_TYPE_HIDDEN,CORE_OSD_TYPE_TEXT,CORE_OSD_TYPE_FILEMOUNTER,CORE_OSD_TYPE_FILELOADER,CORE_OSD_TYPE_TRIGGER,CORE_OSD_TYPE_SWITCH};
enum {KEY_S=1,KEY_A,KEY_DOWN,KEY_UP,KEY_ESC,KEY_BACKSPACE,KEY_ENTER,KEY_LEFT,KEY_RIGHT,KEY_DELETE};
enum {SC_BTN_DOWN=1,SC_BTN_UP=2,UI_JOY_ESC=4,SC_BTN_A=8,SC_BTN_B=16,SC_BTN_LEFT=32,SC_BTN_RIGHT=64};
enum {state_main,state_setup,state_about};
struct Option {const char *name;};
struct Item {int type;const char *name,*hotkey;unsigned options_len,val,slot_id;Option options[64];};
struct {Item osd[64];uint8_t osd_len;bool osd_need_save;}core;
struct {char filename[256];bool is_mounted;}file_slots[6];
struct {uint8_t keycode[6];}usb_keyboard_report;
uint16_t joyL=0,joyR=0;
uint8_t curr_osd_item=0,osd_return_state=0,osd_state=0;
bool is_filebrowser=false;
int sent=-1,triggered=-1,ejected=-1,updates=0;
namespace OSD {enum{COLOR_CYAN_I,COLOR_BLACK,COLOR_WHITE,COLOR_YELLOW_I};}
struct Display {
 int x=0,y=0;char rows[24][33];
 Display(){for(auto &r:rows){memset(r,' ',32);r[32]=0;}}
 void setPos(int a,int b){assert(a>=0&&a<32&&b>=0&&b<24);x=a;y=b;}
 void setColor(int,int){}
 void fill(int a,int b,int c,int d,char v){assert(a>=0&&c<32&&b>=0&&d<24);for(int j=b;j<=d;j++)for(int i=a;i<=c;i++)rows[j][i]=v;}
 void print(const char *s){for(;*s;s++){assert(y<24&&x<32);rows[y][x++]=*s;}}
 void print(const String &s){print(s.s.c_str());}
 void update(){updates++;}
 void beginFrame(){}
 void endFrame(){}
}zxosd;
bool mc0511_active(){return true;}
const char *mc0511_status_text(){return "2026-10-28 22:00:00 Wed";}
uint32_t millis(){return 2000;}
void kg_short_name(const char *s,char *d,int n){snprintf(d,n+1,"%.*s",n,s);}
void core_send(int i){sent=i;}
void core_trigger(int i){triggered=i;}
void filebrowser_open(){is_filebrowser=true;}
void app_core_eject(int i){if(core.osd[i].type==CORE_OSD_TYPE_FILEMOUNTER){ejected=i;file_slots[core.osd[i].slot_id].is_mounted=false;core.osd_need_save=true;}}
#include "mc0511_ui.inc"
#include "menu_config.inc"
void key(int k){usb_keyboard_report.keycode[0]=k;mc_menu_key();usb_keyboard_report.keycode[0]=0;}
int main(){
 configure();mc_menu_reset();mc_menu_draw(3);assert(mc_count<=17);
 uint8_t roots[20],root_count=mc_count;memcpy(roots,mc_rows,mc_count);
 for(unsigned r=0;r<root_count;r++) {
  mc_menu_reset();mc_selected=r;auto i=roots[r];
  if(mc_heading(i)) {
   key(KEY_ENTER);assert(mc_page==i);mc_menu_draw(3);assert(mc_count<=17&&mc_rows[0]==255);
   printf("PAGE %s\n",core.osd[i].name);for(auto &line:zxosd.rows)printf("%s\n",line);
   auto count=mc_count;
   for(unsigned row=1;row<count;row++) {
    mc_selected=row;auto j=mc_rows[row];auto &it=core.osd[j];
    if(it.options_len) {
     auto original=it.val;
     for(unsigned n=0;n<it.options_len;n++){key(KEY_RIGHT);assert(sent==j&&it.val==(original+n+1)%it.options_len);mc_menu_draw(3);}
     assert(it.val==original);key(KEY_LEFT);assert(it.val==(original+it.options_len-1)%it.options_len);key(KEY_RIGHT);
    } else if(it.type==CORE_OSD_TYPE_FILEMOUNTER){key(KEY_ENTER);assert(is_filebrowser);is_filebrowser=false;key(KEY_DELETE);assert(ejected==j);}
   }
   key(KEY_ESC);assert(mc_page==0);mc_menu_draw(3);
  } else if(core.osd[i].type==CORE_OSD_TYPE_TRIGGER){key(KEY_ENTER);assert(triggered==i);}
  else {key(KEY_ENTER);assert(is_filebrowser);is_filebrowser=false;}
 }
 mc_menu_reset();mc_menu_rows();key(KEY_UP);assert(mc_selected==mc_count-1);key(KEY_DOWN);assert(mc_selected==0);
 key(KEY_S);assert(osd_state==state_setup);osd_state=state_main;key(KEY_A);assert(osd_state==state_about);
 osd_state=state_main;mc0511_ui_tick();assert(updates==1);
 puts("PASS: every submenu, bounded display, all choices including 60 minutes, file slots, triggers, ejection, wrap and setup/about");
}
