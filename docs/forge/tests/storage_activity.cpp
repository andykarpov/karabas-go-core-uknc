#include <cassert>
#include <cstdint>
#include <initializer_list>
#include "mc0511_storage.h"
#include "mc0511_identity.h"
static uint32_t now;
static bool active;
static uint32_t millis() { return now; }
static bool mc0511_active() { return active; }
#include "storage_activity_under_test.inc"

int main() {
  for (auto id : {"mc0511", "mc0511                          ", " \tmc0511\r\n"}) assert(mc0511_id_matches(id));
  for (auto id : {"", " ", "mc051", "mc05110", "mc0511-extra", "tsconf", "MC0511"}) assert(!mc0511_id_matches(id));
  assert(!mc0511_oled_defer());
  mc0511_hdd_access(4); // Other cores keep their animation.
  assert(!mc0511_oled_defer());
  active = true;
  mc0511_hdd_access(0); // Floppy access does not freeze the logo.
  assert(!mc0511_oled_defer());
  mc0511_hdd_access(4);
  assert(mc0511_oled_defer());
  now = 99; assert(mc0511_oled_defer());
  now = 100; assert(!mc0511_oled_defer());
  now = 0xfffffff0; mc0511_hdd_access(4);
  now = 0x53; assert(mc0511_oled_defer());
  now = 0x54; assert(!mc0511_oled_defer());
  for (now = 200; now < 1000; now += 5) {
    mc0511_hdd_access(4);
    assert(mc0511_oled_defer());
  }
  now = 1095; assert(!mc0511_oled_defer());
}
