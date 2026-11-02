"""Sample HDD service phases without changing the sector/link protocol."""
from prepare import replace


def timed(s, statement, stage, variable):
    return replace(s, statement, f'uint32_t {variable} = hdd_stamp();\n  {statement}\n  hdd_elapsed({stage}, {variable});')


def adapt_link(s):
    s = replace(s, '#include "main.h"', '#include "main.h"\n#include "hdd_profile.h"')
    # Original guards, clock changes and wire operations are retained.
    a = s.index('static void spi_xfer(')
    b = s.index('// multi-byte values', a)
    part = s[a:b]
    for code, stage, var in [
        ('spi_bus_lock();', 'HP_FRAME_INNER_LOCK', 'p_inner'),
        ('SPI.beginTransaction(link_settings());', 'HP_FRAME_BEGIN', 'p_begin'),
        ('gpio_put(PIN_MCU_SPI_CS, LOW);\n  SPI.transfer(tx, rx, 3);\n  gpio_put(PIN_MCU_SPI_CS, HIGH);', 'HP_FRAME_WIRE', 'p_wire'),
        ('SPI.endTransaction();', 'HP_FRAME_END', 'p_end'),
        ('spi_bus_unlock();', 'HP_FRAME_UNLOCK', 'p_unlock'),
        ('if (in_dispatch_context()) link_dispatch_pending();', 'HP_FRAME_DISPATCH', 'p_dispatch'),
    ]:
        part = timed(part, code, stage, var)
    part = replace(part, 'void spi_send(uint8_t cmd, uint8_t addr, uint8_t data) {',
                   'void spi_send(uint8_t cmd, uint8_t addr, uint8_t data) {\n  uint32_t p_outer = hdd_stamp();')
    part = replace(part, '    SpiBusGuard bus;',
                   '    SpiBusGuard bus;\n    hdd_elapsed(HP_FRAME_OUTER_LOCK, p_outer);')
    s = s[:a] + part + s[b:]
    a = s.index('size_t link_burst_write(')
    part = s[a:]
    part = replace(part, '  SpiBusGuard bus;', '''  uint32_t p_lock = hdd_stamp();
  SpiBusGuard bus;
  hdd_elapsed(HP_BURST_LOCK, p_lock);''')
    for code, stage, var in [
        ('SPISettings settings = link_settings();\n  SPI.beginTransaction(settings);', 'HP_BURST_BEGIN', 'p_begin'),
        ('if (burst_mhz) spi_set_baudrate(spi0, burst_mhz * 1000000UL);', 'HP_BAUD_SET', 'p_set'),
        ('SPI.transfer(hdr, nullptr, sizeof(hdr));', 'HP_HEADER', 'p_header'),
        ('SPI.transfer(data + sent, nullptr, n);', 'HP_PAYLOAD', 'p_payload'),
        ('if (burst_mhz) spi_set_baudrate(spi0, settings.getClockFreq());', 'HP_BAUD_RESTORE', 'p_restore'),
        ('SPI.endTransaction();', 'HP_BURST_END', 'p_end'),
    ]:
        part = timed(part, code, stage, var)
    part = replace(part, '    if (!burst_wait_ready()) {', '''    uint32_t p_ready = hdd_stamp();
    bool ready = burst_wait_ready();
    hdd_elapsed(HP_READY, p_ready);
    if (!ready) {''')
    part = replace(part, '  size_t sent = 0;', '''  if (hdd_profile.active) hdd_profile.spi_hz = spi_get_baudrate(spi0);
  size_t sent = 0;''')
    # Default is byte-for-byte-equivalent clock behavior; the diagnostic AT
    # switch lets us compare the candidate in the same running binary.
    part = replace(part, '  uint32_t p_set = hdd_stamp();', '''  const bool change_baud = burst_mhz && (!hdd_profile.skip_baud ||
    burst_mhz * 1000000UL != settings.getClockFreq());
  uint32_t p_set = hdd_stamp();''')
    part = replace(part, 'if (burst_mhz) spi_set_baudrate(spi0, burst_mhz * 1000000UL);',
                   'if (change_baud) spi_set_baudrate(spi0, burst_mhz * 1000000UL);')
    part = replace(part, 'if (burst_mhz) spi_set_baudrate(spi0, settings.getClockFreq());',
                   'if (change_baud) spi_set_baudrate(spi0, settings.getClockFreq());')
    return s[:a] + part


def adapt(s):
    s = replace(s, '#include "main.h"', '#include "main.h"\n#include "hdd_profile.h"\nHddProfile hdd_profile;')
    s = replace(s, '''  if (!f.isOpen() || !f.seekSet((uint64_t) lba * IMG_SECTOR_SIZE)) return false;
  // a short last sector is padded with zeros
  return f.read(img_buf, IMG_SECTOR_SIZE) > 0;''', '''  uint32_t p_seek = hdd_stamp();
  bool open = f.isOpen() && f.seekSet((uint64_t) lba * IMG_SECTOR_SIZE);
  hdd_elapsed(HP_SD_SEEK, p_seek);
  if (!open) return false;
  // a short last sector is padded with zeros
  uint32_t p_read = hdd_stamp();
  bool ok = f.read(img_buf, IMG_SECTOR_SIZE) > 0;
  hdd_elapsed(HP_SD_READ, p_read);
  return ok;''')
    s = replace(s, '  size_t done = link_burst_write(CMD_IMG_BUF_DATA, 0, img_buf, IMG_SECTOR_SIZE);',
                   '''  size_t done = link_burst_write(CMD_IMG_BUF_DATA, 0, img_buf, IMG_SECTOR_SIZE);
  if (hdd_profile.active && done != IMG_SECTOR_SIZE) ++hdd_profile.fallbacks;''')
    s = timed(s, 'uint16_t sum = img_sum(img_buf);', 'HP_CHECKSUM', 'p_sum')
    s = timed(s, '''spi_send(CMD_IMG_LBA, 0, sum & 0xFF);
  spi_send(CMD_IMG_LBA, 1, sum >> 8);''', 'HP_CHECKSUM_FRAMES', 'p_checks')
    s = replace(s, 'static bool img_serve() {', '''static bool img_serve() {
  const bool next_sample = (hdd_profile.sequence & 63) == 0;
  const uint32_t p_pull = next_sample ? time_us_32() : 0;''')
    s = replace(s, '  SpiBusGuard bus; // the sector and its result stay together on the link', '''  const bool sample = req_op == IMG_REQ_READ && slot == 4 &&
    ((hdd_profile.sequence++ & 63) == 0);
  const uint32_t p_acquire = sample ? time_us_32() : 0;
  SpiBusGuard bus; // the sector and its result stay together on the link
  hdd_profile.active = sample;
  if (sample) {
    hdd_elapsed(HP_IMAGE_LOCK, p_acquire);
    hdd_profile.stage[HP_REQUEST_AGE].add(serve_us - req_start_us);
    hdd_profile.stage[HP_REQUEST_PULL].add(p_acquire - p_pull);
  }''')
    s = timed(s, 'img_send_sector();', 'HP_SEND', 'p_send')
    s = timed(s, 'spi_send(CMD_IMG_SEC, slot, ok ? IMG_RES_DONE : IMG_RES_ERROR);', 'HP_RESULT', 'p_result')
    s = replace(s, '  log_last_ms = millis();', '''  if (hdd_profile.active) {
    hdd_profile.stage[HP_SERVICE].add(took_us);
    ++hdd_profile.samples;
    if (!ok) ++hdd_profile.failures;
    hdd_profile.active = false;
  }
  log_last_ms = millis();''')
    s = replace(s, '  log_rd = log_wr = 0;', '''  if (hdd_profile.samples) {
    static const char *names[HP_STAGE_COUNT] = {
      "request_age", "request_pull", "image_lock", "sd_seek", "sd_read",
      "send_total", "burst_lock", "burst_begin", "baud_set", "ready",
      "header", "payload", "baud_restore", "burst_end", "checksum",
      "checksum_frames", "result", "frame_outer_lock", "frame_inner_lock",
      "frame_begin", "frame_wire", "frame_end", "frame_unlock", "frame_dispatch", "service"
    };
    d_printf("HDD profile: %lu samples (1/64), %lu failures, %lu fallbacks, SPI %lu Hz",
      (unsigned long)hdd_profile.samples, (unsigned long)hdd_profile.failures,
      (unsigned long)hdd_profile.fallbacks, (unsigned long)hdd_profile.spi_hz);
    d_println();
    d_printf("HDD mode: OLED %s, baud setup %s", hdd_profile.pause_oled ? "paused" : "normal",
      hdd_profile.skip_baud ? "skip redundant" : "normal");
    d_println();
    for (unsigned i = 0; i < HP_STAGE_COUNT; ++i) {
      auto &v = hdd_profile.stage[i];
      if (v.count) {
        d_printf("HDD %s: n=%lu avg=%lu max=%lu us", names[i], (unsigned long)v.count,
          (unsigned long)(v.total / v.count), (unsigned long)v.maximum);
        d_println();
      }
      v = {};
    }
    hdd_profile.samples = hdd_profile.failures = hdd_profile.fallbacks = 0;
  }
  log_rd = log_wr = 0;''')
    return s


def adapt_serial(s):
    s = replace(s, '#include "main.h"', '#include "main.h"\n#include "hdd_profile.h"')
    marker = '  if (strcasecmp(arg, "list") == 0) {'
    return replace(s, marker, '''  if (strcasecmp(arg, "hdd-oled-off") == 0 || strcasecmp(arg, "hdd-oled-on") == 0) {
    hdd_profile.pause_oled = strcasecmp(arg, "hdd-oled-off") == 0;
    Serial.print("OK\\r\\n");
  } else if (strcasecmp(arg, "hdd-baud-skip") == 0 || strcasecmp(arg, "hdd-baud-normal") == 0) {
    hdd_profile.skip_baud = strcasecmp(arg, "hdd-baud-skip") == 0;
    Serial.print("OK\\r\\n");
  } else if (strcasecmp(arg, "list") == 0) {''')
