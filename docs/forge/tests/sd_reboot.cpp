#include <cassert>
#include <cstdint>
#include <cstdio>
bool has_sd=true,transfer_active=true,stop_ok=true,flushed=false;
unsigned rebooted=0;
void bk_flush(){flushed=true;}
void d_println(const char*){}
void matrix_icon(unsigned){}
constexpr unsigned MATRIX_ICON_MSC=1,MSC_REQUEST_MAGIC=11,MSC2_REQUEST_MAGIC=12;
struct Card { bool syncDevice(){assert(flushed);if(stop_ok)transfer_active=false;return stop_ok;} } card;
struct Volume { Card *card(){return &::card;} } sd1;
struct Watchdog { unsigned scratch[4]; } watchdog;
Watchdog *watchdog_hw=&watchdog;
struct MCU { void reboot(){assert(!has_sd || !transfer_active);rebooted++;} } rp2040;
#include "msc_reboot_under_test.inc"
int main(){
 for(unsigned slot=1;slot<=2;slot++){
  transfer_active=true;flushed=false;msc_reboot_to_msc(slot);
  assert(rebooted==slot && watchdog.scratch[0]==(slot==1?MSC_REQUEST_MAGIC:MSC2_REQUEST_MAGIC));
 }
 stop_ok=false;transfer_active=true;msc_reboot_to_msc(1);assert(rebooted==2);
 has_sd=false;msc_reboot_to_msc(1);assert(rebooted==3);
 puts("PASS: active SD transfer stopped before reboot; failed stop prevents reboot");
}
