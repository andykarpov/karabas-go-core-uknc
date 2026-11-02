#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <vector>

static uint32_t tick;
static uint32_t time_us_32() { return tick; }
#include "hdd_profile.h"
HddProfile hdd_profile;
static std::vector<uint32_t> events;
static void event(uint32_t value) { events.push_back(value); ++tick; }
static unsigned guards, link_tx_frames, ready_calls, ready_limit;
static bool available, link_rx_enabled = true;
static unsigned burst_mhz = 16, classic_hz = 16000000, current_hz;
static int spi0, link_rx_queue;
static unsigned link_rx_dropped;
constexpr int BURST_MAX_LEN = 512, IMG_SECTOR_SIZE = 512;
constexpr unsigned PIN_BURST_CS = 14, PIN_MCU_SPI_CS = 13, LOW = 0, HIGH = 1;
constexpr uint8_t CMD_IMG_BUF_DATA = 0x45, CMD_IMG_BUF_BANK = 0x44, CMD_IMG_LBA = 0x42;
static uint8_t img_buf[IMG_SECTOR_SIZE];
struct queue_spi_t { uint8_t cmd, addr, data; };
static std::deque<queue_spi_t> replies;
static void spi_bus_lock() { event(0x10000000 | ++guards); }
static void spi_bus_unlock() { assert(guards); event(0x20000000 | guards--); }
struct SpiBusGuard { SpiBusGuard() { spi_bus_lock(); } ~SpiBusGuard() { spi_bus_unlock(); } };
struct SPISettings { unsigned getClockFreq() const { return classic_hz; } };
static SPISettings link_settings() { return {}; }
static bool link_burst_available() { return available; }
static bool burst_wait_ready() { event(0x30000000); return ready_calls++ < ready_limit; }
static void spi_set_baudrate(int, unsigned hz) { assert(guards); current_hz = hz; event(0x40000000 | hz); }
unsigned spi_get_baudrate(int) { return current_hz; }
static void gpio_put(unsigned pin, unsigned level) { assert(guards); event(0x50000000 | pin << 8 | level); }
static void d_println(const char*) { event(0x60000000); }
static bool in_dispatch_context() { return true; }
static bool queue_try_add(int*, const queue_spi_t* p) { assert(guards); replies.push_back(*p); return true; }
static void link_dispatch_pending() {
  while (!replies.empty()) {
    auto p = replies.front(); replies.pop_front();
    event(0x70000000 | p.cmd << 16 | p.addr << 8 | p.data);
  }
}
struct Spi {
  bool active = false;
  void beginTransaction(SPISettings s) { assert(guards && !active); active = true; current_hz = s.getClockFreq(); event(0x80000000 | current_hz); }
  void endTransaction() { assert(active); active = false; event(0x90000000); }
  void transfer(const void* tx, void* rx, size_t n) {
    assert(active && guards);
    event(0xa0000000 | n);
    auto p = static_cast<const uint8_t*>(tx);
    for (size_t i = 0; i < n; ++i) event(p[i]);
    if (rx) {
      assert(n == 3);
      auto r = static_cast<uint8_t*>(rx);
      r[0] = 0x42; r[1] = p[1]; r[2] = p[2];
    }
  }
} SPI;
#include "storage_profile_under_test.inc"

static void run(bool sample, bool burst, unsigned limit) {
  events.clear(); replies.clear(); hdd_profile = {};
  ready_calls = link_tx_frames = link_rx_dropped = 0;
  ready_limit = limit; available = burst;
  {
    SpiBusGuard sector;
    hdd_profile.active = sample;
    img_send_sector();
    hdd_profile.active = false;
  }
  assert(!guards && !SPI.active && replies.empty() && !link_rx_dropped);
  assert(link_tx_frames == (burst && limit ? 3u : 516u));
#if NORMALIZE_BAUD
  unsigned baud_events = 0;
  for (auto e : events) if ((e & 0xf0000000) == 0x40000000) ++baud_events;
  assert(baud_events == (burst && !OPTIMIZED ? 2u : 0u));
  // Only redundant normal-frequency setup and inner recursive locking differ.
  std::vector<uint32_t> normalized;
  unsigned inner_locks = 0, inner_unlocks = 0, outer_locks = 0, outer_unlocks = 0;
  for (auto e : events) {
    if (e == 0x10000003) { ++inner_locks; continue; }
    if (e == 0x20000003) { ++inner_unlocks; continue; }
    if (e == 0x10000002) { ++outer_locks; continue; }
    if (e == 0x20000002) { ++outer_unlocks; continue; }
    if (e != (0x40000000 | classic_hz)) normalized.push_back(e);
  }
  assert(inner_locks == (OPTIMIZED ? 0 : link_tx_frames - unsigned(burst && limit)));
  assert(inner_unlocks == inner_locks);
  assert(outer_locks == (OPTIMIZED ? 0 : link_tx_frames - unsigned(burst && limit) + unsigned(burst)));
  assert(outer_unlocks == outer_locks);
  events = normalized;
#endif
#if PROFILED
  assert(hdd_profile.stage[HP_CHECKSUM].count == unsigned(sample));
  assert(hdd_profile.stage[HP_CHECKSUM_FRAMES].count == unsigned(sample));
  assert(hdd_profile.stage[HP_PAYLOAD].count == unsigned(sample && burst && limit));
  assert(hdd_profile.fallbacks == unsigned(sample && !(burst && limit)));
#endif
  uint64_t hash = 14695981039346656037ull;
  for (auto e : events) { hash ^= e; hash *= 1099511628211ull; }
  printf("wire burst=%d ready=%u sample=%d events=%zu hash=%016llx\n",
    burst, limit, sample, events.size(), (unsigned long long)hash);
}
int main() {
  // CAPS and other direct users retain spi_xfer's own lock. spi_send keeps
  // its outer lock through reply publication even without a sector guard.
  uint8_t rx[3];
  spi_xfer(1, 2, 3, rx);
  assert(!guards && !SPI.active);
  spi_send(1, 2, 3);
  assert(!guards && !SPI.active && replies.empty());
  for (unsigned i = 0; i < sizeof(img_buf); ++i) img_buf[i] = (i * 37 + 11) & 255;
  for (bool sample : {false, true}) {
    run(sample, true, 100);
    run(sample, true, 0);
    run(sample, false, 100);
  }
  // Partial burst must restore the original clock and keep the sent prefix.
  uint8_t data[1024] = {};
  available = true; ready_calls = 0; ready_limit = 1; burst_mhz = 24;
  assert(link_burst_write(0x45, 0, data, sizeof(data)) == 512);
  assert(current_hz == classic_hz && !guards && !SPI.active);
#if PROFILED || OPTIMIZED
  // The live switch skips only redundant setup. Unequal clocks still restore,
  // including READY failure and partial transfers.
  for (unsigned mhz : {0u, 16u, 24u}) {
    for (unsigned limit : {0u, 1u, 2u}) {
      events.clear(); hdd_profile.skip_baud = true;
      ready_calls = 0; ready_limit = limit; burst_mhz = mhz;
      assert(link_burst_write(0x45, 0, data, sizeof(data)) == 512 * limit);
      unsigned changes = 0;
      for (auto e : events) if ((e & 0xf0000000) == 0x40000000) ++changes;
      assert(changes == (mhz == 24 ? 2u : 0u));
      assert(current_hz == classic_hz && !guards && !SPI.active);
    }
  }
#endif
  // Unsigned timing subtraction survives the hardware microsecond wrap.
  hdd_profile = {}; hdd_profile.active = true; tick = 0xfffffff0;
  auto start = hdd_stamp(); tick = 0x20; hdd_elapsed(HP_READY, start);
  assert(hdd_profile.stage[HP_READY].total == 48 && hdd_profile.stage[HP_READY].maximum == 48);
}
