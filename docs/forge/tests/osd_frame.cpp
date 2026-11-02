#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include "OSD.h"
#include "osd_frame_under_test.inc"

struct Screen {
  uint8_t data[26][32] = {}, attr[26][32] = {}, x = 0, y = 0;
  unsigned frames = 0;
} reference, optimized;
static Screen *screen;
static void send(uint8_t cmd, uint8_t addr, uint8_t value) {
  assert(cmd == CMD_OSD);
  ++screen->frames;
  switch(addr) {
    case ADDR_SET_POS_X: screen->x = value; break;
    case ADDR_SET_POS_Y: screen->y = value; break;
    case ADDR_CHAR: screen->data[screen->y][screen->x] = value; break;
    case ADDR_ATTR: screen->attr[screen->y][screen->x] = value; break;
    default: assert(false);
  }
}
static void paint(OSD &osd, unsigned selected, unsigned length) {
  osd.clear();
  for (unsigned row = 3; row < 23; ++row) {
    osd.setColor(OSD::COLOR_WHITE, row == selected ? OSD::COLOR_YELLOW_I : OSD::COLOR_BLACK);
    osd.setPos(0, row);
    for (unsigned x = 0; x < length; ++x) osd.write('A' + row % 26);
  }
}
int main() {
  OSD a, b; a.begin(send); b.begin(send);
  unsigned old_frames = 0, new_frames = 0;
  for (unsigned step = 0; step < 200; ++step) {
    auto selected = step ? (step / 2) % 20 + 3 : 3;
    auto length = step < 100 ? 30 : 8; // Shorter text must erase the old suffix.
    reference.frames = optimized.frames = 0;
    paint(a, selected, length); screen = &reference; a.update();
    b.beginFrame(); paint(b, selected, length); b.endFrame();
    screen = &optimized; b.update();
    assert(!memcmp(reference.data, optimized.data, sizeof(reference.data)));
    assert(!memcmp(reference.attr, optimized.attr, sizeof(reference.attr)));
    if (step == 1) assert(!optimized.frames); // Identical clear/paint is free.
    if (step == 2) { old_frames = reference.frames; new_frames = optimized.frames; }
  }
  b.setPos(31, 25); b.write('!'); // A pre-existing pending write survives a batch.
  b.beginFrame(); b.endFrame(); screen = &optimized; b.update();
  assert(optimized.data[25][31] == '!');
  assert(new_frames < old_frames / 4);
  printf("PASS identical OSD pixels/attributes, pending writes, text erasure; navigation %u -> %u SPI frames\n", old_frames, new_frames);
}
