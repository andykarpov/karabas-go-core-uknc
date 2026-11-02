# Physical floppy mapping — build 26103100

The previous board wrapper tied FDC_DRIVE to `11` and FDC_MOTOR, STEP,
WDATA and WGATE to `1`. GO B4 inverts its floppy signals at the connector:
these values assert the controls. This caused the continuously active drive.
The physical inputs were previously unused; all four UKNC drives were images.

## Controls

`Floppy drives → Physical FDD`: None, A, B, C, D. The default is None, in both
the packaged settings and FPGA register initialization. Invalid settings also
decode to None. A–D map to logical drives 0–3. The mapped drive uses physical
select 0, the same connector selection as physical A in the TSConf core.
This is one physical drive mapped to one UKNC slot, not a second-drive selector.

The mapped slot does not issue image requests. Its mounted image is retained,
and becomes available again when the physical mapping is removed. Other image
slots retain their existing behavior. The slot's OSD write-protect setting is
ORed with the physical write-protect input. Controller Off, reset, host loading,
None, and selection of another logical drive release physical control outputs.

The new OSD item is index 27. Items from the old Hard disk heading onward move
up by one. When installing over an older KG1, migrate saved values by item name
and type; do not copy the old 256-byte settings block wholesale. Physical FDD
must start at None. Preserve the user's image paths separately.

## Implementation

- The source VP1-128 retains its command registers and PPU bus acknowledgement.
  The physical backend observes acknowledged bus cycles and supplies data/status
  reads only for the selected slot. The image backend is stopped and its request
  outputs masked while that slot is selected.
- The 25 MHz receiver synchronizes the cable input, recovers 2 µs MFM channel
  cells, recognizes missing-clock A1, assembles words and checks CRC-CCITT.
  Every new marker group realigns words and starts a fresh CRC, including
  continuous reads across header/data fields without another GDR command.
- The transmitter buffers a word while shifting the previous word, emits A1
  missing-clock markers under WM, and appends CRC on buffer underrun. Pulses
  are 200 ns, words 64 µs, and the data rate is 250 kbit/s. Reading the data
  register or requesting marker search terminates writing.
- STEP has 1 µs direction setup and a 4 µs pulse. The software controls seek
  spacing. READY waits 500 ms after motor start; GO exposes no drive READY pin.
  Track zero, index and write protection are sampled from the physical drive.
- No HD rate or write precompensation is implemented. Physical hardware
  acceptance must establish compatibility with the connected drive and media.

The register/MFM behavior follows the [1801VP1-128 technical description](https://github.com/1801BM1/k1801/blob/master/128/readme.md).
The implementation is core-owned synchronous RTL; no third-party netlist was
copied. Board polarity also follows the supplied `hrdy_fdc.v` adapter and B4
pin/net reference.

## Validation

`python3 tools/test.py tb_physical_fdd` exercises the actual VP1-128 bus alongside
the physical backend: every mapping, virtual fallback, complete 512-byte sectors
at ±2% spindle speed, corrupted CRC rejection, successive fields without GDR,
odd-gap word realignment, TR handshaking, exact outgoing
MFM and CRC pulses, direction/side, step width, both write-protection sources,
and access abort on None, Controller Off and reset.

`python3 tools/test.py tb_board_link` sends actual SPI soft-switch frames through
the full GO wrapper, checking default-off pins, all mappings, invalid values,
controller disable and image-request isolation. `test_menu.py` traverses the
actual firmware's five choices. The B4 audit verifies all 183 signal balls.

`python3 tools/test_physical_boot.py` uses a read-only 300 RPM flux model on
the physical pins and the full machine/ROM. It reuses the machine and memory
scoreboard from `tb_boot` with a smaller host harness; `--trace` records controller
commands. The ordinary `tools/boot.py +DSK=...` retains the image/SPI boot path.
Neither writes the source media.

The 11.66-second full-machine run reaches the [RT-11 banner](evidence/physical-fdd-startup.png),
reads tracks 0–6 on both sides, issues no image requests and completes 17,673,302
memory checks without errors. It does not reach the command prompt in that
window; complete OS startup remains unverified. The banner alone is not a full
boot acceptance result.

The final ISE build passes all constraints with zero setup/hold errors. The
RP2040 firmware is byte-for-byte identical to the previous release. Focused
logs and package hashes are in [the evidence record](evidence/physical-fdd-26103100.txt).

Physical-board read/write/format acceptance remains pending. Unit simulation
does not establish successful reads or writes on a real disk.

## SD1 installation

Build 26103100 was installed on GO `D26610685F233021`, SD1 UUID `3F19-B304`.
All 26 saved switches were migrated by name; all six file picker paths were
preserved. Physical FDD is None. The original card core is backed up under
`build/install-26103100`. An uncached read-only remount matched the installed
bytes exactly. The card was cleanly ejected and the normal serial interface
listed the new build. Select MC-0511 in the core menu to activate it; serial
listing does not establish FPGA boot or physical floppy behavior. The MCU
firmware and other card files were unchanged.
