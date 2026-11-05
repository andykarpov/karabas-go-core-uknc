# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

UKNC (Elektronika MS-0511) on the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25-2, ISE 14.7 (XST).
The machine is [tang-uknc](https://github.com/lordamot/tang-uknc) `7cc4d8e` (Alexey Gurov, Sergei Lemeshev, MIT);
the port to Karabas is by Sergei Lemeshev (lordamot), made in his workspace karabas-forge (core `mc0511`, build
26103102) and moved here on 2026-11-01 (lordamot/karabas-forge#1). This repository does not use the forge
generator: `src/` holds the sources, edited directly. `docs/sources.md` lists the origin of every path and the
changes to the taken files; `docs/forge/` is the archive of the forge core directory (its paths and commands refer
to the forge workspace).

Keep the authorship: `README.md` / `README.ru.md` name the authors of the machine and of the port and the licenses
(GPL-3.0-or-later as a whole; tang-uknc MIT, `docs/licenses/`; the ROMs keep their own terms). Keep both READMEs in
step with the OSD of `core*.json`.

## Layout

- `src/rtl/uknc/`: tang `tang/src` files (patched as in `docs/sources.md`).
- `src/rtl/uknc.v`: the machine (CPU, PPU, memory / video, floppies, IDE, sound, Kakave, UART); the host is in the tops.
- `src/rtl/karabas_<board>_top.v`: kg_pll, kg_mcu, img_sdc (image sectors: FDD0-3 slots 0-3, HDD0 slot 4),
  kg_soft_switches, uknc_keyboard, OSD, video / audio out of the board.
- `src/rtl/uknc_switches.vh`: the OSD switch layout (index = position in the flat `osd` list of `core*.json`, the same
  on every board), `uknc_switch_fields.vh`: their fields. Change all three `core*.json`, the INIT value and the fields
  together.
- No firmware hooks: the forge firmware overlay (Run SAV DSK builder, HDD geometry and RTC seed through
  CMD_SWITCHES 240-245, clock footer 0xF6, /mc0511-media lock) is not used.

## Build

- `cd src && make <board>` (`go`, `mini`, `minig`; steps `<board>-xst`, `-impl`, `-core`; `make <board>-report`).
- Inputs per board: `karabas_<board>.prj`, `.xst` (defines `HW_ID1` Go, `HW_ID2` Mini, `HW_ID2 HW_ID3` Mini G),
  `.ucf`, `.ut`. Every Mini / Mini G top must drive `FT_CLK_OUT` (8 MHz).
- map / par `-ol high`, cost table `-t 2` on every board.
- After a Mini or Mini G build run `make <board>-coremode` (timing of the pixel clock paths without the FT mode constraints, `pcf_core.py`).
- Builds take 10..30 minutes: run them in the background, one board at a time, do not edit RTL while XST runs.
- The `.bin` and `.kg*` files are committed as the release.
