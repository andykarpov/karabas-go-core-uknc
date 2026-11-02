#include "main.h"
#include "mc0511.h"
#include "file_name.h"
#include "app_core.h"
#include "rt11_volume.h"

#include "mc0511_identity.h"
bool mc0511_active() { return mc0511_id_matches(core.id); }
void mc0511_sanitize_slot(uint8_t slot) {
 if(!mc0511_active() || slot>=MAX_FILE_SLOTS) return;
 auto &fs=file_slots[slot];
 if(!mc0511_path_allowed(fs.dir)) strlcpy(fs.dir,MC0511_MEDIA,sizeof(fs.dir));
 if(fs.filename[0] && (!mc0511_path_allowed(fs.dir,fs.filename) || kg_phys_drive(fs.filename)>=0)) {fs.filename[0]=0;fs.is_mounted=false;}
}
// Exact Tang/UKNCBTL HD and ID/WD home-block interpretation.
void mc0511_geometry(uint8_t slot) {
 if(!mc0511_active() || slot!=4) return;
 uint8_t b[512];Mc0511Geometry g={0,0,0,0};
 auto &f=file_slots[slot].file;
 if(f.isOpen() && f.seekSet(0) && f.read(b,sizeof(b))==sizeof(b)) {
  g=mc0511_parse_geometry(b,f.fileSize());f.seekSet(0);
 }
 uint8_t spt=g.spt,heads=g.heads,inv=g.inverted;uint16_t cyl=g.cylinders;
 SpiBusGuard bus;
 spi_send(CMD_SWITCHES,240,spt);spi_send(CMD_SWITCHES,241,heads);spi_send(CMD_SWITCHES,242,inv);
 spi_send(CMD_SWITCHES,243,cyl&255);spi_send(CMD_SWITCHES,244,cyl>>8);
}
static int read_block(void *ctx,unsigned block,void *buf) {
 auto &f=*static_cast<FsFile*>(ctx);return !f.seekSet(uint64_t(block)*512) || f.read(buf,512)!=512;
}
static int write_block(void *ctx,unsigned block,const void *buf) {
 auto &f=*static_cast<FsFile*>(ctx);return !f.seekSet(uint64_t(block)*512) || f.write(buf,512)!=512;
}
static int read_source(void *ctx,uint8_t *buf) {return static_cast<FsFile*>(ctx)->read(buf,512)<0;}
static int setting(const char *name) {
 for(int i=0;i<core.osd_len;i++){String n(core.osd[i].name);n.trim();if(n==name)return i;}return -1;
}
static void send_setting(const char *name,uint8_t value) {
 int i=setting(name);if(i<0)return;core.osd[i].val=value;core_send(i);
}
void mc0511_rtc_seed() {
 if(!mc0511_active())return;
 DateTime dt;if(!zxrtc.now(dt))return;
 // The same fields as Tang's OSD. Each frame is long enough for Kakave's toggle CDC.
 if(dt.year()<2020 || dt.year()>2039)return;
 send_setting("Year",dt.year()-2020);send_setting("Month",dt.month()-1);send_setting("Day",dt.day()-1);
 send_setting("Hour",dt.hour());send_setting("Minute",dt.minute());
 spi_send(CMD_SWITCHES,245,dt.second());
}
static char sav_status[33]="";
void mc0511_run_sav() {
 sav_status[0]=0;
 mc0511_sanitize_slot(5);
 auto &savslot=file_slots[5];
 const char *error=nullptr;
 FsFile base,sav,out;
 static uint8_t buf[4096];
 char prog[8];
 const char *tmp=MC0511_MEDIA "/RT11NEW.TMP";
 const char *dest=MC0511_MEDIA "/RT11SAV.DSK";
 String path=String(savslot.dir)+"/"+savslot.filename;
 zxosd.loadingPopup();zxosd.update();
 // Build a temporary image; keep the mounted disk and template intact on failure.
 if(!mc0511_path_allowed(savslot.dir,savslot.filename)) error="Invalid SAV path";
 else if(!base.open(&sd1,MC0511_MEDIA "/RT11BASE.DSK",O_RDONLY) || base.fileSize()!=819200) error="No valid RT11BASE";
 else if(!sav.open(&sd1,path.c_str(),O_RDONLY) || !sav.fileSize() || sav.fileSize()>819200) error="Invalid SAV file";
 else if(!out.open(&sd1,tmp,O_RDWR|O_CREAT|O_TRUNC)) error="Cannot create DSK";
 if(!error)for(unsigned p=0;p<819200;p+=sizeof(buf)) {
  if(base.read(buf,sizeof(buf))!=sizeof(buf) || out.write(buf,sizeof(buf))!=sizeof(buf)){error="DSK copy failed";break;}
 }
 if(!error) {
  rt11_io_t io={read_block,write_block,&out};
  DateTime dt;unsigned date=zxrtc.now(dt)?rt11sav_date(dt.year(),dt.month(),dt.day()):0;
  if(rt11_build(&io,savslot.filename,sav.fileSize(),date,read_source,&sav,prog,&error) && !error)error="RT11 build failed";
  if(!error && !out.sync())error="DSK sync failed";
 }
 base.close();sav.close();out.close();
 if(!error) {
  // Close every handle to the output before rename, including other floppy slots.
  for(unsigned i=0;i<5;i++)if(String(file_slots[i].dir)==MC0511_MEDIA && String(file_slots[i].filename)=="RT11SAV.DSK") {
   file_slots[i].is_mounted=false;img_mount(i);
  }
  // FAT rename cannot replace. Retain the old run image as a recovery copy.
  sd1.remove(MC0511_MEDIA "/RT11OLD.DSK");
  bool old=sd1.exists(dest);
  if(old && !sd1.rename(dest,MC0511_MEDIA "/RT11OLD.DSK"))error="Cannot retain old DSK";
  if(!error && !sd1.rename(tmp,dest)) {
   if(old)sd1.rename(MC0511_MEDIA "/RT11OLD.DSK",dest);
   error="Cannot install DSK";
  }
 }
 if(!error) {
  auto &fs=file_slots[0];strlcpy(fs.dir,MC0511_MEDIA,sizeof(fs.dir));strlcpy(fs.filename,"RT11SAV.DSK",sizeof(fs.filename));fs.is_mounted=true;
  send_setting("FDD controller",1);img_mount(0);
  for(unsigned i=0;i<core.osd_len;i++)if(core.osd[i].type==CORE_OSD_TYPE_FILEMOUNTER && core.osd[i].slot_id==0)app_core_save(i);
  int reset=setting("Reset");if(reset>=0)core_trigger(reset);
 }
 zxosd.hidePopup();
 if(error){strlcpy(sav_status,error,sizeof(sav_status));d_println(error);zxosd.setPos(0,21);zxosd.print(error);zxosd.update();}
}

static uint8_t clock_fields[8];
static const char *weekdays[]={"---","Sun","Mon","Tue","Wed","Thu","Fri","Sat"};
static char clock_text[32]="Waiting for clock";
void mc0511_register_handlers(){
 link_on(0xf6,[](uint8_t addr,uint8_t data){
  if(!mc0511_active() || addr>=8)return;
  clock_fields[addr]=data;
  if(addr==7)snprintf(clock_text,sizeof(clock_text),"%04u-%02u-%02u %02u:%02u:%02u %s",
    unsigned(clock_fields[0]|clock_fields[1]<<8),clock_fields[2],clock_fields[3],clock_fields[4],clock_fields[5],clock_fields[6],weekdays[clock_fields[7]<8?clock_fields[7]:0]);
 });
}
const char *mc0511_status_text(){return sav_status[0]?sav_status:clock_text;}
