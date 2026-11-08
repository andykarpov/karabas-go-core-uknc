# Sources

Where every path of `src/` comes from, and what was changed in the files taken from other projects.

## tang-uknc (`src/rtl/uknc/`)

[tang-uknc](https://github.com/lordamot/tang-uknc) at `7cc4d8e` (Alexey Gurov, Sergei Lemeshev and
contributors, MIT: [licenses/tang-uknc-MIT.md](licenses/tang-uknc-MIT.md)), the files of `tang/src` in the
same layout. The changes are those of the port in karabas-forge (`docs/forge/tools/prepare.py`,
`port_ide.py`, `port_sdram.py`), applied once to the files:

| File | Change |
|---|---|
| `audio.v` | I2S word select one bit before the MSB (counts 2 / 18, was 3 / 19) |
| `kakave.v` | timer rate `25'd21875000` (was 21937500); a set field 5 = seconds |
| `fdd/fdd4.v` | `sector_ready`: rotation waits in the header / data gap until the sector of the MCU is in the buffer (no stale data with a good synthetic CRC); a read is requested while the sector is not ready; writing to the image (this repository, 2026-11; `write_sd` was never set in tang): the 256 words after the data mark A1 FB of the written stream go to the buffer and the sector goes to the card |
| `xm2-01.v` | the timer on `pin_vm_clk25` with an edge detector of `timer_clk` (was clocked by it) |
| `sdram2.v` | the video phase starts at `horz` 8; DQ driven through an output enable; five refreshes per line (8192-row chip of the Karabas boards); read data in one IOB register bank, its phase and the acknowledgements advance with it (`port_sdram.py retime`) |
| `ide/ide.v` | input `image_sectors`: an invalid CHS or an LBA beyond the image gives ATA IDNF (`bad_location`) instead of a request to the MCU |
| `ppu.v` | output `pin_rom_o` (the cycle reads the firmware ROM) and inputs `pin_rom_ovr_i` / `pin_rom_ovr_dat_i`: a word in place of the ROM word (the kept SETUP colors, `uknc_setup_keep.v`; this repository, 2026-11) |
| `cpu.v` | inputs `pin_clk_slow_i` / `pin_clk_ena_i` to `vm_clk_slow` / `vm_clk_ena` of vm2_wb (were 0): the CPU speed of the OSD, the strobe made in `uknc.v` (this repository, 2026-11) |
| `ay/ym2149.v` | was `ym2149.sv`: Verilog-2001 for XST (no `always_comb`, unpacked arrays, `'{default}`, block-scoped loop variables) |

The other files of the list are unchanged: `aberrant.v covox.v mixer.v mkcolorreg.v vp1_120.v
vp1-128fdd.v vp65.v wmrst.v ide/sd_arbiter.v uart/uart_rx.v uart/uart_tx.v wm2wb/vm2_plm.v wm2wb/vm2_wb.v`.

Not taken: the host of the Tang Nano board (`mister/*`: MCU SPI, sysctrl, sd_card, OSD, HID, flash writer, core
loader), `hdmi/*`, the Gowin IP (`ip/*`, `fdd/ip/*`, `ide/ide_rom.v`), `top.v`.

## The port (karabas-forge mc0511, Sergei Lemeshev)

| Path | From |
|---|---|
| `src/rtl/uknc.v` | the machine of `tang/src/top.v` without the Tang host, with the wiring of forge `machine()` (`prepare.py`): memory phase aligned to the PPU clock, PPU held while the MCU is busy, the image size for the IDE bounds, the physical floppy |
| `src/rtl/uknc_memory.v` | forge `mc0511_memory.v`: the ROMs, the sector buffer and the UART FIFO in place of the Gowin IP; ROM paths `roms/`; the sector buffer is RAMB8BWER by hand (XST dropped its second write port when inferring it) |
| `src/rtl/uknc_keyboard.v` | forge `mc0511_keyboard.v`: USB boot report to the UKNC keyboard codes (the table of the MCU firmware of tang `mnano/uknc.h`; the keys `;:`, `'"`, `` `~ ``, `=+` and Insert..PageDown changed to the LAT table of UKNCBTL `ScreenView.cpp`: `: *`, `@`, `; +`, `Ч ^`, Home = Ъ, Insert = СБРОС, Delete = ПОМ, PageUp = СТОП, End = УСТ, PageDown = ИСП; the rows are no longer sent round robin: the modifier rows 5 and 6 (Shift, УПР / АЛФ / ГРАФ) go down before the other rows and up after them, so Shift+key is never sent key first) |
| `src/rtl/uknc_physical_fdd.v`, `uknc_mfm_rx.v`, `uknc_mfm_tx.v` | forge `mc0511_physical_fdd.v`, `mc0511_mfm_*.v` (Go floppy connector) |
| `src/roms/uknc_rom.hex`, `rawtrk.hex` | tang `tang/rom/uknc_rom.mif`, `tang/src/fdd/rom128/rawtrk.mif` (16-bit words, `tools/mif.py`) |
| `src/roms/ide_wdrom.hex` | tang `tang/rom/ide_wdromv0110.bin` (little-endian words) |

The modules were renamed `mc0511_*` -> `uknc_*`.

## Karabas

| Path | From |
|---|---|
| `src/rtl/uknc_setup_keep.v` | new: the colors of the SETUP menu in DS1307 registers 14..20 of kg_mcu (the core EEPROM, `eeprom_bank` 4), put in place of the ROM table 100012 and the terminal templates 112142, 112252 (the real words for the ROM sum of the start test) |
| `src/rtl/karabas_*_top.v` | new, after the tops of karabas-go-core-baseconf / tsconf |
| `src/karabas_*.ucf` | pins of karabas-go-core-baseconf (= tsconf); timing of forge `src/constraints/timing.ucf` with the HDMI part of baseconf |
| `src/karabas_*.xst`, `.ut`, `src/Makefile` | karabas-go-core-baseconf |
| `src/make_core.py` | symlink to `../../karabas-go-tools/make_core/make_core.py` |
| `src/pcf_core.py` | after karabas-go-core-tsconf, with the constraints of this core (pixel clock `clk_vid`) |
| `modules/` | [karabas-go-modules](https://github.com/andykarpov/karabas-go-modules), unchanged (submodule) |

## karabas-forge archive (`docs/forge/`)

The core directory `forge/cores/mc0511` of [karabas-forge](https://github.com/lordamot/karabas-forge) at `c69c884`
without the media (`res/media`, see `res/manifest.json`): plans, validation, hardware tests, the firmware
overlay and the tools. Its paths and commands refer to the forge workspace.
