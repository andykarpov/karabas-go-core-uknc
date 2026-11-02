"""Bound input work and retain only final framebuffer changes in UKNC redraws."""
from prepare import replace


def adapt_input(s):
    return replace(s, '''  while (ui_done != ui_posted) {
    on_keyboard();
    ui_done++;
  }''', '''  if (ui_done != ui_posted) {
    // These notifications share the current keyboard/joystick report; they
    // are not saved key snapshots. Handle that report once, and leave events
    // arriving during the redraw for the next APP iteration.
    const uint32_t target = ui_posted;
    on_keyboard();
    ui_done = target;
  }''')


def adapt_osd_header(s):
    s = replace(s, '  m_cb action;', '''  m_cb action;
  uint8_t frame_data[SIZE_Y][SIZE_X];
  uint8_t frame_attr[SIZE_Y][SIZE_X];
  bool frame_changed[SIZE_Y][SIZE_X];''')
    return replace(s, '  void update(void);', '''  void update(void);
  // A non-nested redraw batch: preserve pending changes, then compare the
  // final image rather than intermediate clear/paint operations.
  void beginFrame();
  void endFrame();''')


def adapt_osd(s):
    return replace(s, 'void OSD::update()', '''void OSD::beginFrame() {
  for (uint8_t y = 0; y < SIZE_Y; ++y) {
    for (uint8_t x = 0; x < SIZE_X; ++x) {
      frame_data[y][x] = data[y][x];
      frame_attr[y][x] = attr[y][x];
      frame_changed[y][x] = changed[y][x];
    }
  }
}

void OSD::endFrame() {
  for (uint8_t y = 0; y < SIZE_Y; ++y) {
    for (uint8_t x = 0; x < SIZE_X; ++x) {
      changed[y][x] = frame_changed[y][x] || frame_data[y][x] != data[y][x] ||
        frame_attr[y][x] != attr[y][x];
    }
  }
}

void OSD::update()''')
