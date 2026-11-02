# Source attribution

The MC-0511 CPU, PPU, bus devices, memory/video generator, floppy engine, IDE cartridge,
Kakave, Aberrant and mixer are derived from the supplied Tang UKNC project by Alexey Gurov,
with v2 updates by Sergei Lemeshev and contributors. Exact revisions are in `config/sources.lock.json`.
The keyboard mapping and RT-11 volume writer come from that project's MCU firmware.

Karabas GO, Mini and Mini G board pins, PLL, SPI transport, sector transfer and OSD are from Andy Karpov's
Karabas GO projects and their modules. The RP2040 implementation is a generated overlay of
`external/karabas-go-firmware`; the source checkout remains unchanged.

The YM2149 implementation retains MikeJ and Sorgelig's BSD-style notice in its source.
Each upstream source retains its original notices. Consult `external/tang-uknc/LICENCE.md`
and the Karabas repositories' licenses before redistribution. Supplied media and ROMs are
kept as user-provided inputs; this port does not grant new redistribution rights to them.

Mini HDMI uses the Karabas modules zhdmi transmitter by François Galea, with Spartan-6
modifications by Andy Karpov (GPL-3.0-or-later notices retained in the referenced sources).
The fixed-clock wrapper and 48 kHz sampler are maintained in this core. Vendor ISE models
are used only in local simulation and are excluded from the release archive.
