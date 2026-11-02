#pragma once
#include <stdint.h>

// APP enables sampling only while it holds the sector's outer SPI guard.
// Link counters therefore have a single writer, even with USB/input tasks.
enum HddStage {
  HP_REQUEST_AGE, HP_REQUEST_PULL, HP_IMAGE_LOCK, HP_SD_SEEK, HP_SD_READ,
  HP_SEND, HP_BURST_LOCK, HP_BURST_BEGIN, HP_BAUD_SET, HP_READY,
  HP_HEADER, HP_PAYLOAD, HP_BAUD_RESTORE, HP_BURST_END,
  HP_CHECKSUM, HP_CHECKSUM_FRAMES, HP_RESULT,
  HP_FRAME_OUTER_LOCK, HP_FRAME_INNER_LOCK, HP_FRAME_BEGIN,
  HP_FRAME_WIRE, HP_FRAME_END, HP_FRAME_UNLOCK, HP_FRAME_DISPATCH,
  HP_SERVICE, HP_STAGE_COUNT
};
struct HddTiming {
  uint32_t count = 0, total = 0, maximum = 0;
  void add(uint32_t elapsed) {
    ++count; total += elapsed;
    if (elapsed > maximum) maximum = elapsed;
  }
};
struct HddProfile {
  bool active = false;
  volatile bool pause_oled = false, skip_baud = false;
  uint32_t sequence = 0, samples = 0, failures = 0, fallbacks = 0;
  uint32_t spi_hz = 0;
  HddTiming stage[HP_STAGE_COUNT];
};
extern HddProfile hdd_profile;
inline uint32_t hdd_stamp() { return hdd_profile.active ? time_us_32() : 0; }
inline void hdd_elapsed(HddStage stage, uint32_t start) {
  if (hdd_profile.active) hdd_profile.stage[stage].add(time_us_32() - start);
}
