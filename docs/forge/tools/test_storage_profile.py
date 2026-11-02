#!/usr/bin/env python3
"""Compare original and instrumented wire traffic, clocks, locks and replies."""
import re
import subprocess
from prepare import ROOT, FORGE

build = ROOT / 'build/hdd-profile-v3/tests'
build.mkdir(parents=True, exist_ok=True)
outputs = []
for profile, root in [(False, FORGE / 'external/karabas-go-firmware'), (True, ROOT / 'build/firmware')]:
    link = (root / 'src/fpga/link.cpp').read_text()
    storage = (root / 'src/storage/img_mount.cpp').read_text()
    body = link[link.index('static void spi_xfer('):link.index('// multi-byte values')]
    body += link[link.index('size_t link_burst_write('):]
    body += storage[storage.index('static uint16_t img_sum('):storage.index('void img_register_handlers(')]
    body += storage[storage.index('static void img_send_sector('):storage.index('static bool img_receive_sector(')]
    (build / 'storage_profile_under_test.inc').write_text(body)
    binary = build / ('profile' if profile else 'original')
    subprocess.run(['g++', '-std=c++11', '-Wall', '-Wextra', '-Werror',
                    f'-DPROFILED={int(profile)}', '-I'+str(build), '-I'+str(ROOT/'tools/profiles'),
                    str(ROOT/'tests/storage_profile.cpp'), '-o', str(binary)], check=True)
    outputs.append(subprocess.check_output([str(binary)], text=True))
assert outputs[0] == outputs[1], 'Profiling changed the SPI/clock/lock/reply transcript'
serial = (ROOT/'build/firmware/src/periph/serial_bridge.cpp').read_text()
commands = sorted(set(re.findall(r'"(hdd-[a-z-]+)"', serial)))
assert len(commands) == 4
parser_src = FORGE/'external/karabas-go-firmware/lib/KarabasCommon/src'
test = '#include "at_cmd.h"\n#include <cassert>\n#include <cstring>\nint main() {\n'
for command in commands:
    test += ('{ kg_at_parser_t p; kg_at_init(&p); '
             f'const char *s="AT+KARABAS={command}\\r"; '
             'kg_at_result_t result=KG_AT_HOLD; '
             'for (; *s; ++s) { result=kg_at_feed(&p,*s); assert(result!=KG_AT_PASS); } '
             f'assert(result==KG_AT_COMMAND && !strcmp(kg_at_arg(&p),"{command}")); }}\n')
test += '}\n'
(build/'commands.cpp').write_text(test)
subprocess.run(['g++', '-std=c++11', '-Wall', '-Wextra', '-Werror', '-I'+str(parser_src),
                str(build/'commands.cpp'), str(parser_src/'at_cmd.cpp'),
                '-o', str(build/'commands')], check=True)
subprocess.run([str(build/'commands')], check=True)
print(outputs[1], end='')
print('PASS identical original/profiled transactions, fallback, partial bursts, counters and timer wrap')
