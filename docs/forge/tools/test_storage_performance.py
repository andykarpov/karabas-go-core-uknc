#!/usr/bin/env python3
"""Compare production transactions to the reference and check OLED idle gating."""
import subprocess
from prepare import ROOT, FORGE

build = ROOT/'build/hdd-production/tests'
build.mkdir(parents=True, exist_ok=True)
outputs = []
for optimized, root in [(False, FORGE/'external/karabas-go-firmware'), (True, ROOT/'build/firmware')]:
    link = (root/'src/fpga/link.cpp').read_text()
    storage = (root/'src/storage/img_mount.cpp').read_text()
    body = link[link.index('static void spi_xfer('):link.index('// multi-byte values')]
    body += link[link.index('size_t link_burst_write'):]
    body += storage[storage.index('static uint16_t img_sum('):storage.index('void img_register_handlers(')]
    body += storage[storage.index('static void img_send_sector('):storage.index('static bool img_receive_sector(')]
    (build/'storage_profile_under_test.inc').write_text(body)
    binary = build/('optimized' if optimized else 'original')
    subprocess.run(['g++', '-std=c++11', '-Wall', '-Wextra', '-Werror', '-DPROFILED=0',
                    '-DNORMALIZE_BAUD=1', f'-DOPTIMIZED={int(optimized)}', '-I'+str(build),
                    '-I'+str(ROOT/'tools/profiles'), str(ROOT/'tests/storage_profile.cpp'),
                    '-o', str(binary)], check=True)
    outputs.append(subprocess.check_output([str(binary)], text=True))
assert outputs[0] == outputs[1], 'Production changed more than redundant setup/locking'
activity = (ROOT/'build/firmware/src/mc0511_storage.cpp').read_text()
(build/'storage_activity_under_test.inc').write_text(activity[activity.index('static Mc0511StorageActivity'):])
subprocess.run(['g++', '-std=c++11', '-Wall', '-Wextra', '-Werror', '-I'+str(build),
                '-I'+str(ROOT/'firmware'), str(ROOT/'tests/storage_activity.cpp'),
                '-o', str(build/'activity')], check=True)
subprocess.run([str(build/'activity')], check=True)
storage = (ROOT/'build/firmware/src/storage/img_mount.cpp').read_text()
(build/'sector_guard_under_test.inc').write_text(storage[storage.index('static bool img_serve()'):storage.index('static void img_log_summary()')])
subprocess.run(['g++', '-std=c++11', '-Wall', '-Wextra', '-Werror', '-I'+str(build),
                str(ROOT/'tests/sector_guard.cpp'), '-o', str(build/'sector_guard')], check=True)
subprocess.run([str(build/'sector_guard')], check=True)
print('PASS production wire/locks/replies, baud restoration/fallback, OLED activity/idle/wrap')
