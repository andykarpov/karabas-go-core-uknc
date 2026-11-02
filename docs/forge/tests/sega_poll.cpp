#include <cassert>
#include <cstdio>
#include <vector>
#include "SegaController.h"
static unsigned long now;
static unsigned busy_us, reads;
static int pin_value = HIGH;
static std::vector<unsigned> events;
unsigned long millis(){return now;}
void pinMode(unsigned, unsigned){}
void digitalWrite(unsigned pin, unsigned value){events.push_back(pin << 8 | value);}
void gpio_put(unsigned pin, unsigned value){digitalWrite(pin,value);}
int gpio_get(unsigned pin){++reads;events.push_back(0x10000 | pin);return pin_value;}
void delayMicroseconds(unsigned n){busy_us+=n;events.push_back(0x20000 | n);}
int main(){
  SegaController sega; sega.begin(1,2,3,4); events.clear();
  for(auto value : {HIGH,LOW}) {
    pin_value=value;
    for(unsigned i=0;i<3;++i){now+=5;sega.getState(true);sega.getState(false);}
  }
  uint64_t hash=14695981039346656037ull;
  for(auto e:events){hash^=e;hash*=1099511628211ull;}
  printf("normal events=%zu reads=%u busy_us=%u hash=%016llx\n",events.size(),reads,busy_us,(unsigned long long)hash);
  assert(reads == 6*8*16 && busy_us == 6*976);
#if ADAPTED
  auto before=events.size(); now+=5;
  sega.getState(true,20);sega.getState(false,20);
  assert(events.size()==before);
  now+=15;sega.getState(true,20);sega.getState(false,20);
  assert(reads == 7*8*16 && busy_us == 7*976);
  now+=5;sega.getState(true);sega.getState(false);
  assert(reads == 8*8*16); // Immediately return to normal polling when idle.
#endif
}
