#pragma once
#include <stdint.h>

// APP writes this state; OLED reads it on the same MCU core. Leave enough idle
// time to distinguish a stopped stream from the gaps between sector requests.
struct Mc0511StorageActivity {
  volatile uint32_t last_ms = 0;
  volatile bool seen = false;
  void note(uint32_t now) { last_ms = now; seen = true; }
  bool busy(uint32_t now) const { return seen && uint32_t(now - last_ms) < 100; }
};
void mc0511_hdd_access(uint8_t slot);
bool mc0511_oled_defer();
