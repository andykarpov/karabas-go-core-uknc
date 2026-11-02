#include <cassert>
#include <cstdint>
static volatile uint32_t ui_done, ui_posted;
static bool input_waiting, during_draw;
static int input_task_handle, notifications, calls;
struct { uint8_t modifier, keycode[6]; } usb_keyboard_report = {};
static void on_keyboard() { ++calls; assert(calls == 1); if (during_draw) ++ui_posted; }
static void xTaskNotifyGive(int) { ++notifications; }
static void hid_kbd_report_sync() {}
static void led_write(int, bool) {}
#include "ui_dispatch_under_test.inc"
int main() {
  ui_posted = 100; input_waiting = true; input_task_handle = 1; during_draw = true;
  input_tick_ui();
  assert(calls == 1 && ui_done == 100 && ui_posted == 101 && notifications == 1);
  for (unsigned i = 0; i < 1000; ++i) {
    calls = 0; input_tick_ui(); // New input on every redraw must still return.
    assert(calls == 1 && ui_posted - ui_done == 1);
  }
  during_draw = false; calls = 0; input_tick_ui();
  assert(calls == 1 && ui_done == ui_posted);
  calls = 0; input_tick_ui(); assert(calls == 0);
  ui_done = 0xfffffffe; ui_posted = 1; calls = 0;
  input_tick_ui(); assert(calls == 1 && ui_done == 1);
}
