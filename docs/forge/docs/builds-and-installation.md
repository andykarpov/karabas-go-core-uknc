# UKNC MC-0511: builds and installation

Build **26103102** includes the renamed **UKNC MC-0511** chooser entry, faster HDD transfers,
clearer Bad Apple voices with distributed HDD pacing, and the responsive OSD fix.

## Choose your board

| Board | FPGA core on SD1 | RP2040 firmware for RPI-RP2 | Video / audio |
|---|---|---|---|
| Karabas GO B4 | `kg1/mc0511.kg1` | `kg1/mc0511-go-firmware.uf2` | VGA; I2S DAC |
| Karabas Mini (older pin map) | `kg2/mc0511.kg2` | `kg2/mc0511-mini-firmware.uf2` | HDMI with audio; analog stereo |
| Karabas Mini G (rev G) | `kg3/mc0511.kg3` | `kg3/mc0511-minig-firmware.uf2` | HDMI with audio; I2S DAC |

Paths in this table are relative to the extracted release archive, or to the core's `bin/`
directory. Mini and Mini G use different pin mappings: use the pair for your actual board.
The `.uf2` files are RP2040 controller firmware; they are not Raspberry Pi Linux images.
All FPGA targets are XC6SLX25-2-FTG256.

**Validation:** GO retains the exact hardware-tested FPGA and RP2040 binaries. On GO, Bad
Apple sustained about 443 sectors/s at HDD delay 750 µs, with good voices and responsive menus.
KG2/KG3 pass ISE synthesis, placement/routing and timing (zero setup/hold errors), real board-wrapper
SPI/OSD/reset/burst simulations, and HDMI audio packet/clock tests. **KG2/KG3 still require physical
board testing**; GO's playback rate and hardware acceptance do not establish Mini performance.
Each directory contains a checksum/provenance `manifest.json`.

## Install

1. Extract `mc0511-26103102-all.zip`. Preserve your current SD1 contents and previous RP2040
   firmware so you can restore your setup if needed.
2. Copy the selected `mc0511.kg1`, `.kg2`, or `.kg3` to the **root of SD1**. Keep its filename.
   Keep the board's existing `boot.kg1`, `boot.kg2`, or `boot.kg3` core browser on the card;
   this bundle does not replace the browser. Remove any older duplicate MC-0511 package
   from the root so the chooser offers one version.
3. Copy the archive's entire `mc0511-media` directory to the root of SD1. Existing modified
   disk images should be retained separately instead of overwritten. The resulting path
   for Bad Apple is `/mc0511-media/bappwd.img`. All eleven supplied media files are included.
4. Eject/unmount SD1 cleanly and return it to the board.
5. Enter RP2040 **BOOTSEL**: hold its **Boot** button, press/release **Reset**, then release
   **Boot**. Alternatively, send `AT+KARABAS=boot` through the board's USB serial port.
6. When the USB drive **RPI-RP2** appears, copy the matching `.uf2` from the table to it.
   The controller restarts automatically. The `.kg*` file belongs on SD1; the `.uf2`
   belongs on RPI-RP2.
7. Select **UKNC MC-0511** in the firmware/core chooser. Use the bundled controller firmware:
   the standard firmware's 32-item/eight-choice OSD limits are too small for this core.

If the board already runs the accepted GO build from the HDD tests, its KG1 and UF2 binaries
are unchanged; reinstalling those is optional. No build or packaging command flashes a board.

## Bad Apple and controls

1. Open the OSD with **Menu+Esc** (the keyboard's GUI/Windows modifier plus Escape).
2. Mount `/mc0511-media/bappwd.img` through **HDD0**.
3. Set **Hard disk → HDD controller → On**, keep **Image format → Auto**, and set
   **HDD delay us → 750**. The unit is **microseconds**, not milliseconds.
4. Set **Hardware → Covox → Both**. Reset with **F12** if needed.
5. At the UKNC boot prompt, select **2**, then **Enter**.

Keep delay 750 for the tested voice quality. Delay 0 removes the spacing between data-word
reads and can distort voices despite a higher average transfer rate.

Menu navigation uses arrows and Enter; Escape/Back returns; Delete ejects an image.
F12 resets; Menu+F12 requests cold boot. For a floppy, select boot option **1**, then Enter.
**Run SAV** uses the included `RT11BASE.DSK` template and creates `RT11SAV.DSK`, keeping the
previous generated disk as `RT11OLD.DSK`.

Mini builds retain the machine/OSD raster on HDMI: 50 MHz pixels, 1600 × 618 total clocks,
1280 × 600 active including doubled horizontal machine pixels, approximately 50.57 Hz.
HDMI carries signed stereo PCM at 48 kHz. Monitor compatibility and analog/DAC output still
need on-board checks. The FT812 video input is unused by this core. Physical floppy support
is GO-only; Mini menus offer only **Physical FDD → None**, and old saved physical-drive
selections are ignored. Image-backed floppy and HDD slots remain available.

## Rebuild from this workspace

From `forge/cores/mc0511/`, with the pinned references, shared local HDL binaries and supplied
ISE Docker image/license already installed:

```sh
# One-time controller build environment, if not already present:
python3 -m venv build/venv
build/venv/bin/pip install platformio

# Refresh shared menu/switch definitions.
python3 tools/configure.py

# Each board has an isolated FPGA build directory.
for board in go mini minig; do
    python3 tools/forge.py --board "$board" prepare || exit
    python3 tools/forge.py --board "$board" elaborate || exit
    python3 tools/forge.py --board "$board" ise || exit
    python3 tools/firmware.py build --board "$board" || exit
done

# Mini wiring and HDMI checks use actual generated sources.
for board in mini minig; do
    python3 tools/test_boards.py --board "$board" || exit
    python3 tools/test_hdmi.py --board "$board" || exit
done
python3 tools/test_ui_progress.py
python3 tools/test_storage_performance.py
python3 tools/test_sega_poll.py
python3 tools/test_menu.py
python3 tools/test_sd_reboot.py

python3 tools/bundle.py --board all
python3 tools/release.py
```

Use `--board go`, `mini`, or `minig` before the `forge.py` command; GO is the default.
FPGA outputs/logs are in `build/kg1`, `build/kg2`, `build/kg3`. Controller binaries are in
`build/firmware/.pio/build/<board>/firmware.uf2`; board-specific completion records bind them
to their generated source hashes. Build controller targets sequentially because they share
the generated source directory. The controller's pinned platform and dependencies stay in
`build/platformio` and `.pio`.

`bundle.py` verifies source and binary hashes against completed builds and checks timing
before copying artifacts to `bin/kg1`, `bin/kg2`, `bin/kg3`. Hardware acceptance is attached
only when the exact tested hashes match. `release.py` independently checks package headers,
FPGA payloads, menus, UF2 blocks and checksums, then writes the ZIP, including media and these
instructions. It excludes vendor simulation models and build intermediates.

To stage supplied media directly instead of extracting the ZIP:

```sh
python3 tools/media.py --sd1-root /path/to/mounted/SD1
```

This copies, flushes and hash-checks the media and refuses to replace a differing file. It
does not format the card. See [validation](validation.md), [HDD measurements](hdd-performance.md),
and [source attribution](attribution.md) for coverage and provenance.
