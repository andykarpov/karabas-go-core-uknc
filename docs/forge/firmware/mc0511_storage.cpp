#include "main.h"
#include "mc0511.h"
#include "mc0511_storage.h"

static Mc0511StorageActivity activity;
void mc0511_hdd_access(uint8_t slot) {
  if (slot == 4 && mc0511_active()) activity.note(millis());
}
bool mc0511_oled_defer() { return activity.busy(millis()); }
