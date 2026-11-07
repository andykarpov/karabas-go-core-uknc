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
| Run SAV | runs a `.SAV` program in RT-11 (firmware 26110520 or newer): the disk `RT11SAV.DSK` is made from `RT11BASE.DSK` of `/mc0511-media`, an RT-11 system disk you put there, mounted in FDD0 and the machine reset; the disk before it stays as `RT11OLD.DSK` |
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

## Build

ISE 14.7: `cd src && make go` (or `mini`, `minig`); see [CLAUDE.md](CLAUDE.md).
