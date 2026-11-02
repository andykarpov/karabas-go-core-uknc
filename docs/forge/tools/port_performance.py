"""HDD improvements measured with the live OLED/baud comparison."""
from prepare import replace


def adapt_link(s):
    a = s.index('static void spi_xfer(')
    b = s.index('// multi-byte values', a)
    part = s[a:b]
    part = replace(part, 'uint8_t rx[3]) {', 'uint8_t rx[3], bool bus_owned = false) {')
    part = replace(part, '  spi_bus_lock();', '  if (!bus_owned) spi_bus_lock();')
    part = replace(part, '  spi_bus_unlock();', '  if (!bus_owned) spi_bus_unlock();')
    part = replace(part, 'spi_xfer(cmd, addr, data, rx); // recursive lock; outer guard stays held',
                   'spi_xfer(cmd, addr, data, rx, true); // outer guard covers transfer and reply publication')
    s = s[:a] + part + s[b:]
    # Publish under the caller's guard, preserving exactly the same RX FIFO
    # and dispatch point. Sector service already owns the bus throughout.
    a = s.index('void spi_send(uint8_t')
    b = s.index('// multi-byte values', a)
    s = s[:a] + '''static void spi_publish_owned(uint8_t cmd, uint8_t addr, uint8_t data) {
  uint8_t rx[3];
  spi_xfer(cmd, addr, data, rx, true);
  if ((rx[0] > 0) && link_rx_enabled) {
    queue_spi_t packet = { rx[0], rx[1], rx[2] };
    if (!queue_try_add(&link_rx_queue, &packet)) link_rx_dropped++;
  }
}

void spi_send_owned(uint8_t cmd, uint8_t addr, uint8_t data) {
  spi_publish_owned(cmd, addr, data);
  if (in_dispatch_context()) link_dispatch_pending();
}

void spi_send(uint8_t cmd, uint8_t addr, uint8_t data) {
  {
    SpiBusGuard bus;
    spi_publish_owned(cmd, addr, data);
  }
  if (in_dispatch_context()) link_dispatch_pending();
}

''' + s[b:]
    s = replace(s, '  if (burst_mhz) spi_set_baudrate(spi0, burst_mhz * 1000000UL);',
                '''  // beginTransaction already selected the normal clock. Avoid the SDK's
  // divisor search when the burst requests that same clock.
  const bool change_baud = burst_mhz && burst_mhz * 1000000UL != settings.getClockFreq();
  if (change_baud) spi_set_baudrate(spi0, burst_mhz * 1000000UL);''')
    s = replace(s, '  if (burst_mhz) spi_set_baudrate(spi0, settings.getClockFreq());',
                '  if (change_baud) spi_set_baudrate(spi0, settings.getClockFreq());')
    a = s.index('size_t link_burst_write(')
    part = s[a:]
    part = replace(part, 'size_t link_burst_write(', 'size_t link_burst_write_owned(')
    part = replace(part, '  SpiBusGuard bus;\n', '')
    return s[:a] + part + '''
size_t link_burst_write(uint8_t type, uint32_t addr, const uint8_t *data, size_t len) {
  if (!link_burst_available()) return 0;
  SpiBusGuard bus;
  return link_burst_write_owned(type, addr, data, len);
}
'''


def adapt_link_header(s):
    return s + '''
// Caller must hold SpiBusGuard through transfer and reply publication.
void spi_send_owned(uint8_t cmd, uint8_t addr, uint8_t data);
size_t link_burst_write_owned(uint8_t type, uint32_t addr, const uint8_t *data, size_t len);
'''


def adapt_storage(s):
    s = replace(s, '#include "main.h"', '#include "main.h"\n#include "mc0511_storage.h"')
    s = replace(s, '  uint8_t slot = req_slot;',
                '  uint8_t slot = req_slot;\n  mc0511_hdd_access(slot);')
    s = replace(s, 'static bool img_serve() {', '''static bool img_serve() {
  SpiBusGuard bus; // request, sector and result remain ordered under one guard''')
    s = replace(s, '  SpiBusGuard bus; // the sector and its result stay together on the link\n', '')
    a = s.index('static void img_send_sector(')
    b = s.index('static void img_log_summary()', a)
    part = s[a:b].replace('spi_send(', 'spi_send_owned(').replace('link_burst_write(', 'link_burst_write_owned(')
    return s[:a] + part + s[b:]


def adapt_oled(s):
    s = replace(s, '#include "main.h"', '#include "main.h"\n#include "mc0511_storage.h"')
    return replace(s, '  if (!has_oled) return;',
                   '  if (!has_oled || mc0511_oled_defer()) return;')


def adapt_sega_header(s):
    return replace(s, 'uint16_t getState(bool left);',
                   'uint16_t getState(bool left, unsigned long read_delay_ms = SC_READ_DELAY_MS);')


def adapt_sega(s):
    s = replace(s, 'word SegaController::getState(bool left)',
                'word SegaController::getState(bool left, unsigned long read_delay_ms)')
    return replace(s, ' < SC_READ_DELAY_MS)', ' < read_delay_ms)')


def adapt_go_board(s):
    s = '#include "mc0511_storage.h"\n' + s
    return replace(s, '''  left = sega.getState(true);
  right = sega.getState(false);''', '''  // An 8-phase physical-pad scan busy-waits for about 1 ms. During
  // UKNC HDD streams, poll at 50 Hz; USB events still wake INPUT immediately.
  const unsigned long interval = mc0511_oled_defer() ? 20 : SC_READ_DELAY_MS;
  left = sega.getState(true, interval);
  right = sega.getState(false, interval);''')
