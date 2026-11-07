# Ядро УКНЦ (Электроника МС-0511) для Karabas Go / Mini / Mini G

[English version](README.md)

Учебный компьютер **УКНЦ** (Электроника МС-0511, два процессора 1801ВМ2) на платах семейства Karabas Go
(Xilinx Spartan-6 XC6SLX25): ЦП и ПП с памятью и видео, четыре дисковода (образы DSK, на Go физический
дисковод), картридж жёсткого диска IDE с WD ROM (файлы образов), мышь и часы Kakave, три AY платы Aberrant,
бипер, оба порта Covox и последовательный порт C2.

Один файл ядра `uknc.kg` для всех плат (прошивка 26110415 или новее).

| Плата | Видео | Звук |
|---|---|---|
| Karabas Go | VGA | I2S ЦАП (PCM5102) |
| Karabas Mini | HDMI | HDMI, аналоговый выход (sigma-delta) |
| Karabas Mini G | HDMI | HDMI, I2S ЦАП (PCM5102) |

## Авторы

- **Машина**: [tang-uknc](https://github.com/lordamot/tang-uknc) на `7cc4d8e`, УКНЦ для Tang Nano 20K:
  схемотехника **Алексей Гуров**, версия 2 **Сергей Лемешев** и соавторы; эталон UKNCBTL (nzeemin),
  периферия xrust. MIT, [docs/licenses/tang-uknc-MIT.md](docs/licenses/tang-uknc-MIT.md).
- **Порт на Karabas** сделал **Сергей Лемешев** ([lordamot](https://github.com/lordamot)) в октябре 2026 в своём
  рабочем репозитории [karabas-forge](https://github.com/lordamot/karabas-forge) (ядро `mc0511`); с его согласия
  он перенесён сюда ([karabas-forge#1](https://github.com/lordamot/karabas-forge/issues/1)). История порта
  (планы, проверки, тесты на железе) хранится в [docs/forge](docs/forge/README.md).
- Обёртки плат и общие модули [karabas-go-modules](https://github.com/andykarpov/karabas-go-modules) (связь с
  MCU, файлы образов, OSD, PLL, HDMI на **zhdmi** François Galea): Andy Karpov и соавторы.
- YM2149 сохраняет BSD-подобное уведомление MikeJ и Sorgelig.

Происхождение каждого файла и изменения во взятых файлах: [docs/sources.md](docs/sources.md).

## Лицензия

В целом GPL-3.0-or-later, см. [LICENSE](LICENSE) (передатчик zhdmi и модули Karabas); tang-uknc под MIT; каждый
файл сохраняет свой заголовок. Образы ПЗУ в `src/roms` (ПЗУ УКНЦ, WD IDE ROM) это неизменённые данные своих
проектов, на них действуют их исходные условия.

## Использование

Скопируйте `uknc.kg` на SD-карту (SD1), образы дисков в `/mc0511-media` (папка файловых пунктов по
умолчанию). OSD открывается Menu (Win) + Esc.

| Пункт | |
|---|---|
| FDD0, HDD0 | образ DSK дисковода 0, образ IMG жёсткого диска (нужно Hard disk / HDD controller On) |
| Kakave mouse, RTC controller | картридж Kakave+: USB-мышь, часы реального времени |
| Color | RGB / BGR |
| Run SAV | запуск программы `.SAV` в RT-11 (прошивка 26110520 или новее): из `RT11BASE.DSK` в `/mc0511-media`, системного диска RT-11, который вы кладёте туда сами, собирается диск `RT11SAV.DSK`, монтируется в FDD0, и машина сбрасывается; предыдущий диск остаётся как `RT11OLD.DSK` |
| Reset (F12) | сброс машины |
| Sound | громкость, бипер, Covox (порт 177372, 177100 LPT или оба), AY1-AY3, стерео, фильтр, old freaks |
| Floppy drives | контроллер FDD, образы FDD1-FDD3, защита записи каждого дисковода, физический дисковод (Go: A-D) |
| Hard disk | контроллер HDD, защита записи, формат образа (авто / прямой / инверсный), задержка HDD |

Клавиатура: буквы и цифры стоят на своих латинских местах (раскладка ЙЦУКЕН УКНЦ: Q = Я, W = В и т. д.),
знаки и служебные клавиши как в UKNCBTL:

| ПК | УКНЦ | ПК | УКНЦ |
|---|---|---|---|
| `-` | `- =` | `;` | `: *` |
| `=` | `Ч ^` | `'` | `Ю @` |
| `` ` `` | `; +` | `\` | `Э \` |
| `[` `]` | `Ш [` `Щ ]` | Home | `Ъ` |
| Esc | АР2 | Caps Lock | ФИКС |
| Ctrl / Alt / правый Alt | УПР / АЛФ / ГРАФ | F1-F5 | К1-К5 |
| F6 / F7 / F8 | ПОМ / УСТ / ИСП | F9, Insert | СБРОС |
| F10, PageUp | СТОП | Delete / End / PageDown | ПОМ / УСТ / ИСП |

## Сборка

ISE 14.7: `cd src && make go` (или `mini`, `minig`); см. [CLAUDE.md](CLAUDE.md).
