# UKNC (Elektronika MS-0511) core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

The Soviet educational computer **UKNC** (Elektronika MS-0511, two 1801VM2 processors) on the Karabas Go family
of boards (Xilinx Spartan-6 XC6SLX25): the CPU and the PPU with their memory and video, four floppy drives (DSK
images, the physical drive on the Go), the IDE hard disk cartridge with the WD ROM (image files), the Kakave
mouse and real-time clock, the three AYs of the Aberrant card, the beeper, both Covox ports and the C2 serial port.

One core file `uknc.kg` for all the boards (firmware 26110415 or newer).

| Board | Video | Audio |
|---|---|---|
| Karabas Go | VGA | I2S DAC (PCM5102) |
| Karabas Mini | HDMI | HDMI, analog output (sigma-delta) |
| Karabas Mini G | HDMI | HDMI, I2S DAC (PCM5102) |

## Authors

- **The machine**: [tang-uknc](https://github.com/lordamot/tang-uknc) at `7cc4d8e`, the UKNC for the Tang
  Nano 20K: hardware design **Alexey Gurov**, v2 by **Sergei Lemeshev** and contributors; UKNCBTL
  (nzeemin) as the reference, peripherals by xrust. MIT, [docs/licenses/tang-uknc-MIT.md](docs/licenses/tang-uknc-MIT.md).
- **The port to Karabas** is the work of **Sergei Lemeshev** ([lordamot](https://github.com/lordamot)), made in
  October 2026 in his workspace [karabas-forge](https://github.com/lordamot/karabas-forge) (core `mc0511`) and
  moved into this repository with his agreement ([karabas-forge#1](https://github.com/lordamot/karabas-forge/issues/1)).
  Its history (plans, validation, hardware tests) is kept in [docs/forge](docs/forge/README.md).
- The board tops and the shared modules of [karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)
  (the MCU link, image files, OSD, PLL, HDMI with **zhdmi** of François Galea): Andy Karpov and contributors.
- The YM2149 keeps the BSD-style notice of MikeJ and Sorgelig.

The origin of every source file and the changes made to the taken files are in [docs/sources.md](docs/sources.md).

## License

GPL-3.0-or-later as a whole, see [LICENSE](LICENSE) (the zhdmi transmitter and the Karabas modules); tang-uknc is
MIT; every source file keeps its own header. The ROM images in `src/roms` (UKNC ROM, WD IDE ROM) are unchanged
data of their projects and keep their original terms.

## Using it

Copy `uknc.kg` to the SD card (SD1) and the disk images to `/mc0511-media` (the default folder of
the file items). The OSD opens with Menu (Win) + Esc.

| Item | |
|---|---|
| FDD0, HDD0 | DSK image of drive 0, IMG image of the hard disk (needs Hard disk / HDD controller On) |
| Kakave mouse, RTC controller | the Kakave+ cartridge: USB mouse, real-time clock |
| Color | RGB / BGR |
| Run SAV | runs a `.SAV` program in RT-11 (firmware 26110716 or newer; 26110520..26110715 reboot when the file is chosen): the disk `RT11SAV.DSK` is made from `RT11BASE.DSK` (or `BASERT11.DSK`, its name in `soft/` of tang-uknc) of `/mc0511-media`, an RT-11 system disk you put there, mounted in FDD0 and the machine reset; the disk before it stays as `RT11OLD.DSK` |
| CPU speed | slows the CPU down: Fast (as before) or 1/2, 1/2.5, 1/3, 1/3.5, 1/4, 1/5, 1/6 of it. The core runs the programs faster than a real UKNC (about 3.5 times), so games may be too quick: choose the value by them. The PPU (screen, sound, keyboard) keeps its speed |
| Reset (F12) | reset of the machine |
| Sound | volume, beeper, Covox (port 177372, 177100 LPT or both), AY1-AY3, stereo, low-pass, old freaks |
| Floppy drives | FDD controller, FDD1-FDD3 images, write protection of each drive, physical drive (Go: A-D) |
| Hard disk | HDD controller, write protection, image format (auto / plain / inversed), HDD delay |

Keyboard: the letters and digits are on their Latin places (the UKNC JCUKEN layout: Q = Я, W = В and so on),
the punctuation and the service keys as in UKNCBTL:

| PC | UKNC | PC | UKNC |
|---|---|---|---|
| `-` | `- =` | `;` | `: *` |
| `=` | `Ч ^` | `'` | `Ю @` |
| `` ` `` | `; +` | `\` | `Э \` |
| `[` `]` | `Ш [` `Щ ]` | Home | `Ъ` |
| Esc | АР2 (AR2) | Caps Lock | ФИКС (FIX) |
| Ctrl / Alt / right Alt | УПР / АЛФ / ГРАФ | F1-F5 | К1-К5 |
| F6 / F7 / F8 | ПОМ / УСТ / ИСП (HELP / SET / EXEC) | F9, Insert | СБРОС (RESET) |
| F10, PageUp | СТОП (STOP) | Delete / End / PageDown | ПОМ / УСТ / ИСП |
| Keypad: digits, `.`, `-`, `+`, Enter | the same keys of the UKNC keypad | Keypad `/` / `*` | `/ ?` / `: *` |

Notes:

- The layout is **positional**, as in UKNCBTL: a PC key presses the UKNC key in its place and the UKNC
  picks the character by its own keyboard. So the shifted characters often differ from the PC: `:` is
  `;` **without** Shift, Shift+`;` gives `*`; `=` is Shift+`-`; `+` is Shift+`` ` ``; Shift+2 gives `"`,
  not `@` (`@` is the `'` key); Shift+`'` gives `` ` ``. Shift with the digits as printed on the UKNC keys
  (Shift+1 = `!`, Shift+3 = `#` and so on).
- The PC `=` key is `Ч ^`: `^` in LAT mode (drawn as `¬` by the UKNC font), Ч in RUS mode.
- Num Lock is ignored: the keypad is always the UKNC keypad. The PC has no key for the comma of the
  UKNC keypad.
- The UKNC keyboard sends the keys by the rows of its matrix, and two keys of one row can't be held
  together: pressing the second one releases the first. Hence two limits: Shift can't be combined with
  7, 8, 9 and `-` of the keypad (the same row), and УПР / АЛФ / ГРАФ can't be combined with Esc (АР2),
  Tab, 0 and Enter of the keypad.
- Shift, УПР, АЛФ and ГРАФ always reach the machine before the key pressed with them and are released
  after it (УПР+C breaks a program in RT-11).
- F12 resets the machine (the Reset item), Menu (Win) + Esc opens the OSD.

### SETUP colors are kept

The colors of the SETUP menu of the UKNC (F7, УСТ: 3 symbol, 4 cell, 5 screen, 6 cursor) stay after a reset
and power off: the core keeps them in the EEPROM of the core, the file `/config/uknc.eep` of the SD card
(firmware with kgo2 cores). For green on black choose symbol 3 (green), cell 1 and screen 1 (black). The
other items of the menu (VT-52, format, scroll, timer) are not kept, nor the colors set by programs with ESC
sequences. Deleting `/config/uknc.eep` gives white on blue again.

### RT-11 versions

A game that stops at once with `*** СТОП ***` (the HALT instruction) may need another RT-11, this is not a
fault of the core. Some `.SAV` programs keep code in block 0, at 500..776, but after loading a program the
RT-11 monitor writes the block map of that program into low memory:

| RT-11 | System disk | Where the map goes |
|---|---|---|
| V05.04 | `BASERT11.DSK` of tang-uknc | 540..557 |
| V05.02 | `sys1002.dsk` | 514..533 |
| V5.01a | `sysimage.dsk` | inside the monitor, low memory stays intact |

For example, `LAND.SAV` of `game.dsk` stops with `000556/0000` on V05.04 and works on `sysimage.dsk`
([uknc.narod.ru/DSK](https://uknc.narod.ru/DSK/index.htm)). `game.dsk` has other programs with data at
540..557 (SEEKER, GARDEN, CAT, VERT, MAUS, TETUK, DIGGER), they were not tried. Run SAV boots the system
disk you put in `/mc0511-media`, so the same applies to it.

## Build

ISE 14.7: `cd src && make go` (or `mini`, `minig`); see [CLAUDE.md](CLAUDE.md).
