#include <cassert>
#include <cstdint>
#include <cstddef>
static unsigned guards, acquisitions, pulls, reads, sends, results, writes;
struct SpiBusGuard { SpiBusGuard(){++guards;++acquisitions;} ~SpiBusGuard(){--guards;} };
static bool req_started, req_pending, req_complete, read_ok = true;
static uint8_t req_slot, req_op;
static uint32_t req_lba, req_start_us;
constexpr int IMG_REQ_POLLS = 32;
constexpr unsigned IMG_REQ_READ = 1, IMG_REQ_WRITE = 2;
constexpr unsigned IMG_SECTOR_SIZE = 512, MAX_FILE_SLOTS = 5;
constexpr unsigned CMD_NOP = 0, CMD_IMG_SEC = 0x43, IMG_RES_DONE = 1, IMG_RES_ERROR = 2;
static uint8_t img_buf[IMG_SECTOR_SIZE];
static unsigned last_result;
static void spi_send_owned(unsigned cmd, unsigned, unsigned result) {
  assert(guards == 1);
  if (cmd == CMD_NOP) { if (++pulls == 4) {req_started = false; req_pending = true;} }
  else {assert(cmd == CMD_IMG_SEC); ++results; last_result = result;}
}
struct FsFile {
  bool isOpen(){assert(guards == 1);return true;}
  bool seekSet(uint64_t){assert(guards == 1);return true;}
  size_t write(const uint8_t*,size_t n){assert(guards == 1);++writes;return n;}
};
struct Slot { FsFile file; } file_slots[MAX_FILE_SLOTS];
static bool img_dirty[MAX_FILE_SLOTS];
static uint32_t img_last_write_ms, log_rd, log_wr, log_first_ms, log_last_ms;
static uint32_t log_max_wait_us, log_max_serve_us, log_slots;
static uint32_t micros(){return 100;}
static uint32_t millis(){return 1;}
static void mc0511_hdd_access(uint8_t){assert(guards == 1);}
static bool img_read_sector(FsFile&, uint32_t){assert(guards == 1);++reads;return read_ok;}
static void img_send_sector(){assert(guards == 1);++sends;}
static bool img_receive_sector(){assert(guards == 1);return true;}
static void matrix_drive_access(uint8_t, uint32_t, bool){assert(guards == 1);}
template<class... T> static void d_printf(const char*,T...){}
static void d_println(){}
#include "sector_guard_under_test.inc"
int main(){
  assert(!img_serve() && !guards && acquisitions == 1);
  acquisitions = 0; req_started = req_complete = true; req_slot = 4; req_op = IMG_REQ_READ;
  assert(img_serve() && !guards && acquisitions == 1);
  assert(pulls == 4 && reads == 1 && sends == 1 && results == 1 && last_result == IMG_RES_DONE);
  req_pending = true; read_ok = false;
  assert(img_serve() && !guards && last_result == IMG_RES_ERROR);
  req_pending = true; req_op = IMG_REQ_WRITE;
  assert(img_serve() && !guards && writes == 1 && img_dirty[4] && last_result == IMG_RES_DONE);
  req_pending = true; req_complete = false;
  assert(img_serve() && !guards && last_result == IMG_RES_ERROR && writes == 1);
}
