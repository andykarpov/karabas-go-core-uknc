# KG1 adaptation

`tools/prepare.py` takes the active Tang project source list and generates an ISE tree without
editing the reference repositories. `config/sources.lock.json` pins revisions; `res/manifest.json`
pins the supplied media. Preparation rejects changed revisions or media hashes. The generated
manifest covers every HDL, initialization, project and constraint file used by ISE.

The retained machine includes both VM2 processors, ROM, video/RAM arbitration, four floppy
slots, IDE cartridge/WD ROM, keyboard controller, Kakave mouse/RTC, Aberrant's three AYs, beeper,
both Covox ports, filters and C2 UART. The source explicitly has no joystick port. Tang's BL616,
SD transport, OSD and HDMI are replaced by the Karabas RP2040 link, checked image-sector bridge,
Karabas OSD, VGA and the GO DAC. Tang's core-selection menu maps to the standard Karabas chooser;
settings save through the standard core-file mechanism.

GO's RP2040 IO names and FPGA vector indices are reversed: burst chip-select is RP2040 IO0
(GPIO14), FPGA `MCU_SPI_IO[1]` at M11; ready is RP2040 IO1 (GPIO2), FPGA `MCU_SPI_IO[0]` at N9.
The board-link regression instantiates the full wrapper with the firmware's input pull-up/pull-down
states and checks capability replies, OSD, reset release, burst payload and classic-frame recovery.
This catches logical wiring errors that a ball-to-net constraint audit cannot detect.

## GO audio interface

The source serializer changes data on PPU rising edges. The GO wrapper forwards an inverted
PPU clock through ODDR2, so the PCM5102 samples half a cycle later. Word-select changes one
bit before each MSB (source counts 3/19 were simultaneous with the MSB; the port uses 2/18).
The native pin decoder checks complete signed left/right words and both least-significant bits.
DIN/LRCK output routes are constrained to 20 ns against a 160 ns half-cycle. The PCM5102
requires 8 ns data and word-select setup/hold around BCK rising; see
[TI's audio-interface timing specification](https://www.ti.com/lit/ds/symlink/pcm5102.pdf).
Physical listening and signal measurements remain board acceptance work.

## Clocks and external memory

A 400 MHz Spartan-6 PLL supplies 50 MHz memory/video, 25 MHz host, 4.166667 MHz CPU and
3.125 MHz PPU clocks through BUFGs. The host's 180-degree phase preserves its relationship to
PPU/memory phases. Memory startup aligns its phase counter to a PPU edge. No fabric divider is
used as a machine clock. The timer's former muxed data clock is now a host-clock enable.

The GO B4 BOM identifies MT48LC16M16A2TG SDRAM. Unlike the Tang package SDRAM, this is a discrete
8192-row part. Five refresh commands per 32 us scanline complete a refresh sweep in under
64 ms. Each reserved refresh slot is 320 ns. Startup retains the source's >1 ms settling delay,
precharge, two refreshes and mode load.

One IOB input register bank captures SDRAM data. The qualified read phase and its data advance
together, including acknowledgements; the video serializer bypasses the just-captured green/red
word when needed. The memory scoreboard covers byte enables, address aliases and both processors.

The forwarded SDRAM PLL output is +56.25 degrees (3.125 ns at 50 MHz). Constraints limit command/
data outputs to 5 ns and pad-to-input-register capture to 4 ns. The routed timing report includes
both fast/slow clock-to-pad paths; external board acceptance remains necessary. No timing paths
were disabled to hide the clock or SDRAM failures found during development. The inherited board
pin constraint permits general routing of MCU_SCK because its physical ball is fixed; SPI is
explicitly constrained at 16 MHz.

References: [Micron SDRAM specifications](https://www.alliancememory.com/wp-content/uploads/Micron_256M_SDRAM_PartNo.MT48LC16M16A2.pdf),
[Spartan-6 block RAM guide](https://docs.amd.com/api/khub/documents/Xs~b~O94R6gZSgSD34Yh5Q/content).
The ISE RAMB8 initialization warning is covered by using ISE 14.7 without bitstream encryption;
no non-default primitive INIT_FILE attribute is used.

## Host, storage and menus

The 16 MHz SPI link carries USB reports, switches and OSD updates. Image reads use the negotiated
burst link and an end-to-end byte count/checksum. The sector bridge and source arbiter separate
floppy and HDD ownership; writes copy the outgoing sector before sending it. Floppies hold in
the header/data gap when a delayed MCU response has not filled the buffer, preventing stale data
from appearing with the source's synthetic CRC indication.

The mounted HDD's actual sector count also reaches IDE. Invalid CHS (including WDINIT's
sector-zero probe) and LBAs outside the image return ATA IDNF without entering the retrying
SPI transport. The bounds regression checks reads, writes and recovery to the last valid sector.

`tools/configure.py` generates menu metadata and HDL indices together. Zero-option hidden
records delimit Karabas-rendered submenus. The firmware uses a bounded option pool for the
larger lists and validates counts and slot indices. Restrictions are applied both to the browser
and persisted paths at image-open time. Physical-drive entries are disabled for this core.

Run SAV uses the source RT-11 volume algorithm. It builds and syncs a temporary copy of RT11BASE,
preserves system-file placement, installs the SAV and startup command, retains the old generated
image, mounts FDD0 and resets. Both SAV fixtures are checked against extracted program bytes and
unchanged boot/system files. RTC starts from the GO battery clock when its year is in the menu's
2020–2039 range; register writes and live readback remain in the FPGA Kakave implementation.
