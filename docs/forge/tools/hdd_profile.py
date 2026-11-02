#!/usr/bin/env python3
"""Send a temporary HDD profiling switch and capture one bounded interval."""
import argparse
import os
from pathlib import Path
import select
import termios
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('command', choices=['listen', 'hdd-oled-off', 'hdd-oled-on',
                                      'hdd-baud-skip', 'hdd-baud-normal'])
parser.add_argument('output', type=Path, help='New log path relative to the core build directory')
parser.add_argument('--seconds', type=float, default=35)
parser.add_argument('--serial', default='D26610685F233021')
args = parser.parse_args()
if not 1 <= args.seconds <= 60:
    parser.error('Capture duration must be 1..60 seconds')
port = Path('/dev/serial/by-id') / f'usb-Karabas_Go_{args.serial}-if00'
device = Path('/sys/class/tty') / port.resolve().name / 'device'
usb = next((p for p in device.resolve().parents if (p/'idVendor').exists()), None)
identity = {k: (usb/k).read_text().strip() for k in ['idVendor', 'idProduct', 'serial']} if usb else {}
if identity != dict(idVendor='2e8a', idProduct='000a', serial=args.serial):
    parser.error(f'Unexpected USB identity: {identity}')
output = (ROOT/'build'/args.output).resolve()
if not output.is_relative_to(ROOT/'build'):
    parser.error('Output must stay inside the core build directory')
output.parent.mkdir(parents=True, exist_ok=True)
captured = bytearray()
with output.open('xb', buffering=0) as log:
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        settings = termios.tcgetattr(fd)
        settings[0] = settings[1] = settings[3] = 0
        settings[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        settings[4] = settings[5] = termios.B115200
        settings[6][termios.VMIN] = settings[6][termios.VTIME] = 0
        termios.tcsetattr(fd, termios.TCSANOW, settings)
        if args.command != 'listen':
            os.write(fd, f'AT+KARABAS={args.command}\r\n'.encode('ascii'))
        deadline = time.monotonic() + args.seconds
        while time.monotonic() < deadline:
            if select.select([fd], [], [], min(.2, max(0, deadline-time.monotonic())))[0]:
                data = os.read(fd, 65536)
                if not data:
                    raise RuntimeError('Board disconnected during capture')
                log.write(data)
                captured.extend(data)
    finally:
        os.close(fd)
print(captured.decode(errors='replace'), end='')
if args.command != 'listen' and b'OK' not in captured.splitlines():
    raise SystemExit('Command was not acknowledged; inspect the log')
