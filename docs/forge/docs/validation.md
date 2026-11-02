# MC-0511 KG1 validation

## Firmware chooser name: 26103102

The installed chooser label is `UKNC MC-0511`. The KG1 differs from 26103101
only in name/build metadata. An initial MCU optimization was rolled back;
a subsequent controlled test measured 251–252 sectors/s normally and 379
with OLED animation paused and redundant SPI clock setup skipped. Further
request-path and polling improvements reach about 443 sectors/s at delay
750 us in the final MCU build. The user confirmed responsive menu navigation
after the OSD backlog correction and good Bad Apple sound with this build.
These are targeted checks, not acceptance of every hardware feature. Saved
switches and picker paths were preserved and the card was verified after an
uncached, read-only remount. See the [measurements and firmware state](hdd-performance.md).

## OSD spacing update: 26103101

The MC0511 raster has 1600 clocks per line. The inherited overlay scaled its
character positions by four while repeating normal font pixels only twice,
leaving blank space within each cell. The core-owned `tools/port_osd.py` adapter
now indexes each bitmap using the scaled horizontal position and commits the
next bitmap/attribute at the cell boundary. Popups use the same positioning
with doubled pixels and a complete popup-cell read-ahead.

`python3 tools/test.py tb_osd` checks 4,500,000 output pixels through the actual
command-loaded font and character RAMs: 400/800/1600-clock lines, 625-line
frames, normal/popup modes, all visible rows/columns, asymmetric glyphs,
adjacent colors, border clipping, dimmed video and disabled-overlay passthrough.
Full board elaboration, board-link and physical-floppy regressions pass.
ISE placement/routing passes all constraints with zero setup/hold errors.
See [the regression and build evidence](evidence/osd-26103101.txt).
This update retains the 26103100 physical-floppy implementation and existing
RP2040 firmware. Hardware visual acceptance remains pending.

Installed to SD1 on GO `D26610685F233021`; uncached read-back matches the
staged package, and the serial core listing confirms `26103101`. All 27 saved
switches and six file-picker paths were preserved, including Physical FDD=None.
The card was cleanly unmounted/ejected. Select MC-0511 in the board's core menu
to activate it; the available serial protocol cannot select a core.

## Physical FDD update: 26103100

The new `Physical FDD` menu choice defaults to None and maps one physical drive
to A/B/C/D. It fixes the old wrapper's asserted idle signals and adds a physical
MFM read/write backend. See [implementation and focused validation](physical-fdd.md).
This update uses the existing 26102802 RP2040 firmware; no firmware reflash is
needed. Physical-drive acceptance is pending. The earlier hardware results
below apply to their stated builds, not to the new floppy backend.

## Earlier hardware and media validation

Build 26102802 is a hardware-test candidate. The FPGA and RP2040 firmware build successfully;
the user confirmed physical UKNC boot and OSD with build 26102801, and file visibility plus
KKVTST.SAV launch with build 26102802. Remaining media/peripheral acceptance
is still in progress. The FPGA package requires the accompanying firmware
for the expanded menus, restricted media browser and SAV preparation.

## Verified locally

- Full board elaboration and GO B4 pin audit: 183 signal balls, no duplicates or net mismatches.
- ISE 14.7 synthesis, placement, routing and TRCE: **all constraints met, zero setup/hold errors**.
  The routed design uses about 62% of LX25 LUTs, 18% of registers and 65% of 18K block RAMs.
  Exact reports and input hashes are in `build/kg1`; packaging rejects stale or failed builds.
- RP2040 `go` firmware build passes. It is a core-owned overlay of the pinned shared firmware;
  the reference checkout is unchanged.
- Source regressions: Covox, hardware enables, keyboard buffering, interrupt arbitration,
  SD arbitration, IDE, mixer, Aberrant and Kakave mouse/RTC. Kakave's seven seconds are exactly
  21,875,000 PPU clocks at the KG1's 3.125 MHz.
- USB keyboard adapter: modifier chords, releases and same-row rollover.
- Board DAC pin test: 194 exact stereo I2S words, including both least-significant bits.
  The port advances the inherited serializer's word-select by one bit and inverts the
  forwarded BCK, so DIN/LRCK change at the DAC's falling edge with 160 ns nominal setup.
- The actual menu implementation runs against the actual core configuration in a native
  character-display test: every submenu, all option values (including 60 minutes), bounded
  rows/columns, image selectors, triggers, ejection, cursor wrap and Setup/About transitions.
  This checks menu logic and layout bounds; it does not replace on-board rendering/input tests.
- IDE bus regression through the actual MCU SPI and checked sector bridge: CHS, LBA28,
  plain/inverted data, write protection, complete checksummed writes, read-ahead, cancelled
  requests and programmable delay; zero errors. Prefetch waits account for SPI transfer time.
- Invalid CHS sector/head and reads/writes at EOF return ATA IDNF without touching media;
  the next valid request recovers correctly. This prevents WDINIT's invalid-address probe
  from entering a transport retry loop.
- All four floppy slots tolerate a deliberately delayed 30 ms host response: 1,024 exact
  data words, no stale-buffer data exposed before the complete sector arrives.
- Complete machine boot: both processors, SDRAM, video and physical SPI frames/bursts.
  The generated `KKVTST.DSK` boots RT-11 and launches `KKVTST.SAV` from `STARTS.COM`.
  The 13.7-second run reads 584 sectors and checks 21,202,986 memory bytes with zero mismatches.
  See [the captured test-program screen](evidence/sav-kkvtst.png).
- `TSTVM2.SAV` also launches through its generated RT-11 disk and begins reporting successful
  CPU instruction tests. Its 13.7-second run checks 22,637,924 memory bytes with zero mismatches.
  [Captured processor-test screen](evidence/sav-tstvm2.png); this is startup evidence, not
  a claim that the complete instruction suite has finished.
- `bappwd.img` boots and starts BadApple video over the same physical SPI sector path:
  1,690 sectors and 10,612,826 checked memory bytes, zero mismatches in 5.7 simulated seconds.
  [Captured BadApple frame](evidence/badapple.png). Full playback and physical audio remain pending.
  A repeat with the final IDE bounds fix captures a [later video frame](evidence/badapple-final.png):
  2,733 reads, no writes, 15,103,860 checked memory bytes and zero errors in 7.8 simulated seconds
  (`build/badapple-final-bounds`).
- The plain `WDC170inv_P.img` successfully loads WDROM and presents its partition selector.
  [Captured partition prompt](evidence/hdd-plain-menu.png). Partition 0 boots RT-11;
  its startup script requires writes. A RAM-only copy-on-write backend verifies 214 reads,
  18 complete checksummed writes and 21,235,146 memory bytes with zero mismatches. The source
  IMG remains read-only. With write protection enabled, RT-11 reports its expected startup
  write failures ([capture](evidence/hdd-plain-protected.png)).
- Dice Wars reaches its [game menu](evidence/dicewars.png): 15,883,754 active memory-byte
  comparisons, zero errors. The scoreboard qualifies responses with the request strobe;
  an idle completion of a sampled write is not a new read of the old bus address.
- [PT3X20](evidence/PT3X20.png) reaches its music player and
  [Darkroom](evidence/darkroom-v1.0.0.png) its title/start screen, with respectively
  26,924,982 and 26,821,532 active memory-byte comparisons and zero errors.
- [RT11BASE](evidence/rt11base.png) and the [mouse/Covox utility disk](evidence/utilities.png)
  boot to their RT-11 command prompts. The utility disk does not automatically run MOUTST.
- [WDINIT with the supplied plain HDD](evidence/wdinit-bounded.png) reaches its device report:
  316 sector reads and 16,430,492 active memory-byte comparisons, zero errors. Its sector-zero
  probe now returns IDNF and execution continues. WDINIT rejects this image's 10-head geometry
  because that program requires 16 heads/63 sectors; no disk initialization was attempted.
- Both provided SAVs: exact extracted payloads, correct `R NAME` startup command, unchanged
  template/boot blocks and unchanged locations/content of the existing system files.
- Both actual HDD headers decode correctly, independently of filenames:
  `bappwd.img` is inverted (109/16/63); `WDC170inv_P.img` is plain (980/10/34).
  Tests also invert each header and verify the same geometry with the opposite encoding.
- Media policy tests reject root escapes, prefix-confusion paths, traversal components,
  backslashes, doubled separators and path-bearing filenames. Physical-drive browser entries
  are suppressed for MC-0511.

## SD1 transfer

All 11 supplied resources are staged, SHA-256 verified, under `build/sd1/mc0511-media`.
The identified GO (`D26610685F233021`) exported SD1 volume `3F19-B304` and received these
files under `/mc0511-media`. The transfer script backed up the existing card files and verified
all copied hashes and all pre-existing file hashes. Evidence and the actual backup are under
`build/sd-transfer`.

Reconnection revealed incomplete writes in both HDD images from the interrupted first transfer.
Their damaged copies were retained under `build/sd-transfer/interrupted-copy`, repaired from
the originals and explicitly synced. After unmounting, flushing block buffers and mounting
read-only, all 11 files passed SHA-256 read-back on 2026-10-28 at 20:17:33 UTC. Every pre-existing
card file remained unchanged. See `build/sd-transfer/readback.json` and `repairs.json`.
The final KG1 was installed after the matching MCU firmware and passed uncached read-back
at 20:34:55 UTC. SD1 was then unmounted and ejected; the GO returned to normal mode and its
serial listing includes `mc0511;Elektronika MC-0511 UKNC;26102800` alongside the nine existing
cores. This establishes installation, not a successful FPGA boot.

## Installed candidate

- GO serial: `D26610685F233021`; physical USB path `3-2`.
- Before the update, picotool saved and verified all 16 MiB of RP2040 flash as
  `build/board/firmware-before.uf2` (32 MiB UF2), SHA-256
  `b3080b7b2cb0d6526d650bc5dcb4da1f3b776ec78560535261b58775f4fe0da8`.
- Installed MCU UF2: SHA-256 `decececfe5fe3bca22e40609f51d575ef10777326989e9791d16710eb4fea243`.
  `picotool load -v -x` verified the flash and rebooted; normal serial commands respond.
- Installed KG1 build 26102802: 749,878 bytes, distribution SHA-256
  `f9ab1dedb2ee80a729fdd6474af945fc72da4ffda066c4bd46e444f492731a5d`.
  The installed copy preserves the user's compatible settings at bytes 512–767; its SHA-256 is
  `fc3b6cb51cf360303eec26fdd2a0d90ecb7bd82548252c71d96e716582ade450`.
  Actual prior files are saved as `build/sd-transfer/mc0511-before-pin-fix.kg1` and
  `mc0511-before-filter-fix.kg1`. Differences were checked bytewise before preserving settings, and
  uncached read-back passed before ejecting the SD export.
- Transfer and firmware evidence: `build/sd-transfer/core-install.json`,
  `build/board/firmware-backup.json`, `firmware-install.json`, and `installed-core-list.log`.

## Remaining acceptance

The user paused work for the day after confirming KKVTST launch. Resume from
[the 29 October handover](handover-2026-10-29.md); no serial capture or transfer remains running.

Build 26102800 failed its first physical test: selectable core, stable black picture, no OSD,
activity indication. The MCU remained responsive and completed the 47-entry menu load, but its
FPGA capability query received no answer. The GO wrapper had swapped burst chip-select and
ready; the MCU's ready pull-down therefore held burst select active and disabled classic frames,
leaving machine reset asserted. `tb_board_link` reproduces the absent reply with the original
mapping and passes after correcting it. Build 26102801 contains the correction; physical retest
now returns `FPGA caps: 03, burst max 16 MHz` in 1 ms and completes menu loading
(`build/board/pin-fix-boot.log`). The user confirmed both the UKNC screen and OSD work.
The first browser attempt showed only its root entry: extension metadata omitted the leading
dot required by Karabas's matcher. Build 26102802 corrects `.dsk`, `.sav`, and `.img` without
changing the routed FPGA. A native regression uses the actual Karabas matcher and padded
metadata for all six slots: seven DSKs, two SAVs and two IMGs are admitted as appropriate.
Switching from the browser to USB export then exposed an SD initialization timeout (0x1E),
recovered by a full power cycle. The firmware now calls `syncDevice()` before MCU-only resets
to USB export or BOOTSEL, ending SdFat's active dedicated-SPI read/write stream. The actual
export routine passes a native regression for active transfers, failed stops, and absent cards.
The updated firmware and filter metadata are installed; a post-browser hardware export retest
remains necessary.
Debug logging is temporarily enabled in `karabas.ini`; the exact prior file is retained
as `build/sd-transfer/karabas-before-debug.ini` and must be restored after diagnosis.

Knight's disk reaches a Russian "press Enter to continue" screen after its startup commands
(`build/knight-extended`, 1,486 reads, 51,161,948 memory-byte checks, zero errors in 31.7 seconds).
Its game launch still needs that interaction and verification. Full BadApple playback,
physical keyboard/mouse, audio pitch/stereo, RTC readback, menu rendering and
navigation, saved settings, and cold/warm reset behavior still require the recorded tests in
[hardware-test.md](hardware-test.md). A serial listing cannot establish these results.

The inherited floppy backend does not persist disk writes: `fdd4.write_sd` is never asserted
in the supplied source. Its protection switches and register behavior are preserved. IDE writes
are implemented and tested. The source also exposes a Cold Boot menu action without a distinct
RAM-clear implementation in its top-level reset wiring; this port preserves that reset behavior.
