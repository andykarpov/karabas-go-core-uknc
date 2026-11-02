# GO B4 acceptance

## Candidate and prerequisites

Use `bin/kg1/mc0511.kg1` together with `bin/kg1/mc0511-go-firmware.uf2` and its manifest.
The MCU update is required: the generic 32-entry/eight-choice menu parser cannot represent this
core's 47 entries, 60-choice minute field and submenus. The overlay preserves the normal menu
renderer for other cores. Do not treat loading the FPGA alone as a valid integration test.

The board was identified over USB as Karabas GO, serial `D26610685F233021`. Re-identify it
before any transfer; Linux device names can change. Use the repository's board-access procedure.
Retain the installed firmware and card files before replacement. Firmware BOOTSEL is a firmware
update operation, not a way to select an FPGA core. Never format the cards.

The provided serial interface can list cores and export SD1/SD2. It cannot select a core,
capture VGA, or inject keyboard/mouse input. Those checks need a person or verified capture/input
hardware. Record the candidate hashes, MCU firmware, board revision and observed output.

## Media and OSD

1. Check SD1 read-back against `res/manifest.json`; preserve existing images/settings.
   All 11 supplied files passed uncached read-back on 2026-10-28; see `build/sd-transfer/readback.json`.
2. Install the candidate MCU firmware using the documented RP2040 UF2 workflow, then add the
   candidate KG1 to SD1. Select UKNC MC-0511 in the Karabas core browser.
3. Check VGA boot against the simulated UKNC loader screen. Open OSD with Menu/Win+Esc.
4. Visit Hardware, Aberrant, Floppy drives, Hard disk, RTC clock, Video and About. Check left/right,
   Enter, Back/Escape, S for Setup and A for About; both global pages must remain usable.
5. Open every image picker. It must start within `/mc0511-media`, show matching extensions and
   subdirectories, and offer no route above that folder or to physical-drive pseudo-files.
6. Change settings, leave/re-enter the core, and verify persistence. Exercise the one-second
   Kakave clock footer without pressing any keys. Check both RGB/BGR choices.

## Programs and devices

- Mount RT11BASE in FDD0, reset and boot disk 0. Repeat with each supplied DSK, using each
  program's own startup controls. Knight's supplied disk pauses at a Russian "press Enter" prompt
  after its startup commands; continue there before judging game startup. Check a four-drive configuration and changing disks while idle.
- Select KKVTST.SAV and TSTVM2.SAV through Run SAV. The generated RT11SAV.DSK must boot RT-11
  and run the selected program. The base template must retain its original hash. Enable the
  Kakave mouse for its test and check motion, buttons, held/released keys and modifiers.
- Enable the RTC and use its test software to set/read it. Compare program reads with the
  OSD footer. A CPU reset must preserve the running clock.
- Enable HDD, mount each supplied IMG in turn and boot the ROM cartridge (loader choice 2,
  cartridge 1). Confirm Auto format and repeat using the matching explicit Plain/Inversed setting.
- For BadApple use bappwd.img, enable Covox as required by its player and start with the retained
  750 us HDD delay. Record picture, sound, speed and sustained playback; adjust delay only with
  an observed reason. A sector-read regression does not prove the demo's complete playback.
- Test the beeper, all three AYs, both Covox addresses, ABC/mono, low-pass, Old freaks and volume.
  Compare pitch and stereo with the source machine. GO uses VGA and the board's I2S DAC.
- Check the inherited C2 serial interface at its configured rate with a loopback or peer.
- Check F12 Reset and Menu+F12 Cold Boot. The supplied FPGA's Cold Boot wiring has no separate
  RAM-clear operation; record actual behavior rather than assuming the source guide's wording.

Do not use the supplied HDDs for destructive write tests. The protocol regression uses a
simulated disk and verifies all write bytes/checksums. Any physical write acceptance should use
an explicitly disposable copy.
