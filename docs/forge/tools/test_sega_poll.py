#!/usr/bin/env python3
"""Verify physical-pad polling changes cadence, not scan waveforms or decoding."""
import subprocess
from prepare import ROOT,FORGE
build=ROOT/'build/sega-poll-tests';build.mkdir(parents=True,exist_ok=True)
(build/'Arduino.h').write_text('''#pragma once
#include <stdint.h>
typedef uint8_t byte;
typedef uint16_t word;
typedef bool boolean;
#define HIGH 1
#define LOW 0
#define OUTPUT 1
#define INPUT_PULLUP 2
#define max(a,b) ((a)>(b)?(a):(b))
#define bitRead(v,b) (((v)>>(b))&1)
unsigned long millis();
void pinMode(unsigned,unsigned);
void digitalWrite(unsigned,unsigned);
void gpio_put(unsigned,unsigned);
int gpio_get(unsigned);
void delayMicroseconds(unsigned);
''')
outputs=[]
for adapted,root in [(False,FORGE/'external/karabas-go-firmware'),(True,ROOT/'build/firmware')]:
    lib=root/'lib/SegaController'
    binary=build/('adapted' if adapted else 'original')
    subprocess.run(['g++','-std=c++11','-Wall','-Wextra','-Werror','-Wno-parentheses',
                    f'-DADAPTED={int(adapted)}','-I'+str(build),'-I'+str(lib),
                    str(ROOT/'tests/sega_poll.cpp'),str(lib/'SegaController.cpp'),'-o',str(binary)],check=True)
    outputs.append(subprocess.check_output([str(binary)],text=True))
assert outputs[0]==outputs[1]
s=(ROOT/'build/firmware/src/board/board_go.cpp').read_text()
body=s[s.index('void board_joy_read('):s.index('void board_reset_peripherals(')]
(build/'board.cpp').write_text('''#include <cassert>
#include <cstdint>
static bool busy;
static unsigned calls;
constexpr unsigned long SC_READ_DELAY_MS=5;
static bool mc0511_oled_defer(){return busy;}
struct Sega { uint16_t getState(bool left,unsigned long interval){
 assert(interval==(busy?20:5));++calls;return left?123:456;
} } sega;
'''+body+'''int main(){uint16_t l,r;for(bool b:{false,true}){busy=b;board_joy_read(l,r);assert(l==123&&r==456);}assert(calls==4);}
'''.replace('for(bool b:{false,true})','for(int b=0;b<2;++b)'))
subprocess.run(['g++','-std=c++11','-Wall','-Wextra','-Werror',str(build/'board.cpp'),'-o',str(build/'board')],check=True)
subprocess.run([str(build/'board')],check=True)
print(outputs[0],end='')
print('PASS identical physical scans, 20 ms busy cadence, normal idle cadence, both GO ports')
