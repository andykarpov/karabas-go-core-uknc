# UKNC MC-0511 — Karabas GO, Mini and Mini G

Port of the supplied `external/tang-uknc` machine to Karabas GO B4, Mini and Mini G (Spartan-6 LX25).
The maintained adapters, firmware overlay and build tools belong to this core. Reference checkouts are not modified.

Packages and matching RP2040 firmware are in `bin/kg1`, `bin/kg2`, and `bin/kg3`.
See **[builds and installation](docs/builds-and-installation.md)** for board selection,
SD1 layout, UF2 installation, Bad Apple settings and multi-board build commands.
The complete archive is [mc0511-26103102-all.zip](bin/mc0511-26103102-all.zip).

GO retains the hardware-tested HDD/audio/menu build. KG2/KG3 pass simulation and routed
ISE timing but still need physical board testing. See [validation](docs/validation.md)
and [board acceptance](docs/hardware-test.md) for the broader feature coverage.

## Build

From this directory:

```sh
python3 tools/configure.py
python3 tools/forge.py prepare
python3 tools/forge.py elaborate
python3 tools/test.py quick
python3 tools/test_physical_boot.py
python3 tools/test_media.py
python3 tools/test_menu.py
python3 tools/test_audio.py
python3 tools/test_storage.py
python3 tools/test_peripherals.py
python3 tools/boot.py
python3 tools/forge.py ise
python3 tools/firmware.py build
python3 tools/test_sd_reboot.py
python3 tools/bundle.py
python3 tools/media.py
```

`ise` uses the Forge ISE Docker adapter. `package` refuses a stale or failed timing build.
Install PlatformIO locally once with `python3 -m venv build/venv` followed by
`build/venv/bin/pip install platformio`. `firmware.py build` prepares the required RP2040
firmware in `build/firmware`, builds its PlatformIO `go` environment and records source/binary
hashes. Downloads stay in `build/platformio`. `bundle.py` regenerates inputs, checks them
against both completed builds, and collects KG1, UF2 and a checksum manifest in `bin/kg1`.
The standard firmware's limits of 32 menu entries and eight choices are insufficient for this machine.
The firmware overlay preserves the standard menus for other cores.

The core-owned OSD adapter keeps font pixels aligned with scaled character
cells, including enlarged popups. `python3 tools/test.py tb_osd` runs its
pixel-level regression (also included in `quick`).

`test_boot_media.py` runs the supplied DSK images and the plain HDD through the complete
machine/SPI bridge, retaining logs and screens under `build/media-boots`. These longer tests
open media read-only. Inspect the screens: successful reads alone do not prove application startup.

`media.py` copies every file under `res/media` to `build/sd1/mc0511-media`, checking SHA-256.
`--sd1-root PATH` stages to an already identified/mounted SD1. It refuses to replace differing files.
No command formats a card or automatically flashes hardware.

## Media and controls

Open the standard Karabas menu (Menu+Esc). The main page has FDD0, Run SAV, HDD0, Reset,
Cold boot and the Hardware, Aberrant, Floppy drives, Hard disk, RTC clock, Video and About submenus.
Enter/right selects; left decrements choices; Escape/Back returns; Delete ejects a mounted image.
F12 resets; Menu+F12 requests cold boot. UKNC F1–F10 retain their source machine key mappings.
Settings persist in the KG1 file using Karabas's standard save behavior.

`Floppy drives → Physical FDD` selects **None (default), A, B, C or D**.
A–D correspond to FDD0–FDD3. The selected slot uses the first physical drive
(GO drive-select 0); the other slots continue using DSK images. Its mounted
image is retained but unused until the mapping is removed. None releases the
physical motor, selects, step and write outputs. The slot's write-protect setting
and the drive's physical write-protect signal both inhibit physical writes.
Use 250 kbit/s DD UKNC media; HD media rates are not implemented.
See [physical floppy implementation and validation](docs/physical-fdd.md).

The MC-0511 media pickers and image opens are confined to SD1 `/mc0511-media` and descendants.
`Run SAV` copies `RT11BASE.DSK`, adds the chosen program and appends `R NAME` to STARTS.COM,
then mounts the generated `RT11SAV.DSK` in FDD0 and resets, as Tang does. The template is never written.
A temporary image is completed and synced first; the previous generated image is retained as `RT11OLD.DSK`.

For BadApple, mount `bappwd.img`, enable the HDD controller and select the required Covox port.
At the UKNC boot prompt choose `2`, then Enter. For `WDC170inv_P.img`, the WDROM additionally
asks for a boot partition (`0`–`5`). For a floppy or a prepared SAV, choose `1`, then Enter.
The source default HDD delay is 750 us per sector; `Auto`, `Plain` and `Inversed` formats are retained.
The image's first sector supplies geometry, including HD and ID/WD home-block formats.

The firmware chooser displays **UKNC MC-0511** (build `26103102`). The GO FPGA
bitstream is unchanged from 26103101; Mini targets have board-specific HDMI/audio wrappers. The MCU avoids redundant SPI setup,
locking and heap allocations; it pauses the OLED logo and scans physical Sega
pads at 50 Hz during UKNC HDD activity. USB input timing is unchanged. Menu
processing is bounded and sends only changed cells. The final build sustains
about **443 sectors/s at HDD delay 750 us**; the user confirmed good sound and
responsive menus. Keep the distributed delay for Bad Apple: delay 0 can produce
distorted voices even when average playback speed is close. See the measured
[HDD transfer investigation](docs/hdd-performance.md).

The port includes C2 UART as well as USB keyboard/mouse, Kakave RTC, three AY chips/Aberrant,
beeper, both Covox ports, four floppy slots and HDD. The supplied source does not persist
floppy writes and does not implement a distinct RAM clear for Cold boot; those source
limitations remain for image-backed floppies. Physical floppy and HDD writes are
supported. Use disposable media for write tests.

Third-party licenses and provenance are described in [attribution](docs/attribution.md).
