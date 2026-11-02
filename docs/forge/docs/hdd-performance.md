# HDD transfer investigation — 26103102

The firmware chooser now names this core `UKNC MC-0511`. The core ID, filename,
FPGA payload, menu indices and settings layout are unchanged from 26103101.

The user reported slow Bad Apple playback from `bappwd.img` with HDD delay 0.
On GO D26610685F233021, the original firmware served 2747 sectors in 10009 ms
and 2751 in 10015 ms (approximately 275 sectors/s). A prior full-machine SPI
simulation reached approximately 502 sectors/s with the default 750 us delay,
so reducing the configured delay alone would not address the hardware result.

The IDE already fetches the next sector while the PPU consumes the current one.
The MCU already uses buffered SD transfers and FPGA burst writes. Added timing
counters separated SD reads from the sector send, including its checksum frames:
the diagnostic baseline averaged 578–591 us on SD, 1696–1713 us sending to FPGA,
and 789–830 us collecting the request. Consecutive repeated LBAs were zero.
That instrumented run sustained approximately 214 sectors/s; it is the closer
comparison for subsequent runs using the same counters. The original and
instrumented rates are separate observations, not interchangeable baselines.

An experiment skipped the two `spi_set_baudrate()` calls in
`link_burst_write()` when normal and burst settings both requested 16 MHz.
Each SDK call searches up to 255 post-divisors, making this a plausible source
of overhead. Host checks passed for clock restoration, payload lengths,
locking and fallback, but hardware did **not** demonstrate an improvement:
the first playback sample averaged 1724 us for the FPGA send. The user confirmed
continued slow playback and reboot loops. Watchdog traces included TS-Conf ROM
loading (step 03a5) and UKNC menu input (0700), with the APP task holding SPI.
The root cause of these hangs was not established; the candidate was rejected.

The experiment was removed from maintained source and the release bundle.
Its files and candidate binary remain under `build/hdd-fast-experiment/` for
diagnosis. No speculative SD cache or higher bus clock was added.

`python3 tools/firmware.py build --profile-storage` creates an opt-in diagnostic
build. `tools/port_storage.py` adds ten-second read-time averages to the existing
image summaries. The detailed profiler samples one HDD sector in 64 and reports
counts, averages and maxima for request handling, the outer sector lock, SD seek
and read, burst lock/setup, both baud-rate calls, READY, header/payload, checksum
calculation/frames, result and classic-frame lock/wire/dispatch phases. It also
records actual SPI baud rate, sampled errors and fallback counts. Parent totals
(`send_total`, `service`, checksum frames) include their child stages: do not add
all rows together. These describe MCU service, not video frame rate.

Sampling is active only while APP owns the outer sector SPI guard; other tasks
cannot write the counters. Unsampled reads retain only conditional checks.
The diagnostic build pauses autoload in the chooser without writing preferences.
`python3 tools/test_storage_profile.py` compares the original and generated
instrumented routines: identical wire bytes, clock changes, lock operations and
reply dispatch, including burst timeout/classic fallback and partial bursts;
it also checks counter gating and microsecond timer wrap.

The detailed v2 capture (`build/hdd-profile-v2/running.log`) sustained 166–168
sectors/s in three ten-second windows, with 26 samples per window, no sampled
errors or fallback, and actual SPI baud 12 MHz. Average SD reads were 553–836 us;
FPGA send totals were 2311–2641 us. The two baud calls together took 904–1166 us,
and the 512-byte payload took 781–819 us. These are wall times, including task
preemption. This binary is slower than the original; do not compare different
instrumented builds as evidence of an optimization.

The board's OLED continuously sends a scrolling-logo frame every 20 ms on the
APP core, at APP priority. A frame uses about 12 ms of busy-polled I2C according
to the reference firmware. V3 adds temporary AT switches for a controlled test
inside one binary: `hdd-oled-off`, `hdd-oled-on`, `hdd-baud-skip` and
`hdd-baud-normal`. Defaults retain OLED refresh and both clock calls. Skipping
baud setup affects only equal requested normal/burst speeds; unequal speeds
still switch and restore, including partial/failed transfers. Commands do not
write preferences. The host test also feeds each command through the actual
AT parser and asserts that none is forwarded to the emulated machine.

`tools/hdd_profile.py COMMAND hdd-profile-v3/NAME.log --seconds 35` identifies
the board and captures one bounded interval. After switching, discard the first
ten-second summary (it can span both settings), and compare complete subsequent
windows. A mode label reports the current switch state, not necessarily the
state of every read in the preceding window. These switches remain diagnostic
until hardware measurements and stability checks support a production change.

Normal preparation/builds omit the counters and restore ordinary autoload;
`bundle.py` regenerates normal sources and rejects a diagnostic-only build.

## Controlled live comparison

The v3 test switched settings during uninterrupted Bad Apple playback at delay
0. Each switch was acknowledged over serial. Summaries before the command and
the first summary after it were excluded, leaving complete ten-second windows.
The initial baseline also excludes its first window. The same binary and 12 MHz
actual SPI clock were used throughout:

| OLED animation | Redundant baud calls | Sectors/s |
| --- | --- | ---: |
| Running | Retained | 251.12 |
| Paused | Retained | 318.57 |
| Paused | Skipped | 379.28 |
| Running | Skipped | 292.38 |
| Running, return to baseline | Retained | 252.44 |
| Paused, repeat | Skipped | 379.13 |

Both changes together improved this instrumented baseline by 51%. Returning to
the baseline reproduced the original rate. No sampled read errors or burst
fallbacks occurred in these windows. Logs and the per-window arithmetic are in
`build/hdd-profile-v3/` and `comparison.json`. This is sector-service throughput,
not a measured video frame rate or proof of real-time audio playback.

The production candidate uses the same baud condition. It defers OLED frames
during UKNC slot-4 activity and for 100 ms after the latest request, so the logo
resumes when the HDD becomes idle. Other cores and floppy-only activity do not
start this deferral. It retains the original bus speeds, checksums, locks and
fallback behavior, and does not include the diagnostic counters/AT switches.
`test_storage_performance.py` compares the actual generated routines to the
reference, allowing only the two redundant baud events to differ, and checks
unequal-clock restoration, partial/failed bursts and the OLED idle/wrap boundary.
The user confirmed faster playback but still below the required speed. They
also reported progressively delayed OSD navigation ending in a reset. The
first production candidate reproduced that failure: `osd-recheck.log` records
APP at `0700` (input processing), SPI held by APP, and the watchdog/USB/timer
still running ten seconds after APP's last progress mark. Playback-only
stability did not establish menu stability.

## OSD backlog correction

The input loop drained `ui_posted` until it matched `ui_done`, including new
events arriving during redraws. Each notification reused the current input
report rather than retaining an individual key snapshot. Slow rendering could
therefore accumulate redundant work and keep APP inside the loop. The overlay
also cleared and repainted the complete screen on every navigation step,
marking unchanged final cells dirty.

The follow-up candidate handles the current report once per APP iteration,
acknowledges notifications already present, and leaves new arrivals pending for
the next iteration. UKNC overlay/clock redraws now compare the final framebuffer
against its pre-draw state while preserving any already-pending writes. The
other screens retain their existing redraw behavior. The watchdog remains
enabled with its original timeout.

`test_ui_progress.py` checks continuous arrivals, idle/catch-up, acknowledgement
and counter wrap. Its framebuffer regression verifies identical pixels and
attributes across navigation and text shortening, pending-write preservation,
and a representative reduction from 2400 to 240 SPI frames per navigation step.
Menu, storage-transaction and SD-reboot regressions also pass. Production
The user subsequently confirmed that the menu works well. Bad Apple still
needs more speed. The production playback capture served approximately
276–318 sectors/s (`build/hdd-production-ui/running.log`), lower than the
instrumented comparison; different binaries are not interchangeable baselines.

## Further service overhead

The next candidate removes the heap allocation in `mc0511_active()` while
preserving the original trimmed, case-sensitive ID match. That function is
used by the new per-sector activity gate as well as UI paths. It also omits
`spi_xfer()`'s recursive lock only when called by `spi_send()`, whose outer
guard still covers the wire transfer and reply publication. Direct callers,
including capability queries, retain the helper's locking. The host transcript
comparison now allows those redundant inner lock/unlock pairs in addition to
the baud calls; wire bytes, reply order and outer guards remain identical.
Direct calls without a sector guard and trimmed/nonmatching IDs are tested.
This candidate sustained approximately 445–447 sectors/s at delay 0, and the
user reported it was almost fast enough. Its verified UF2 is
`db289293b89f95a80acf79b6e30e3f1524fd83eaaeca9074cd099194a7ba6c7d`.
See `build/hdd-service-fast/acceptance.log` and `install.json`.

## Covox timing and the 750 us comparison

The user reported heavily distorted voices and pointed to Tang's earlier
investigation (`external/tang-uknc/prompts/29 bad apple hdd.txt`). That record
and the IDE comments explain that the player takes 52 Covox samples from each
sector. Waiting between sectors creates gaps between bursts of samples and
modulates the waveform; merely approaching the average playback rate does not
remove those gaps. The cartridge's replacement delay distributes extra time
across data-word reads. The GO port retains that logic; delay 0 disables it.

The user changed the setting to **750 microseconds** and confirmed clearer
voices, but playback was still too slow. The serial rate settled near 395
sectors/s (`build/hdd-service-fast/delay-audio.log`). This supports a timing
explanation; it is not a direct capture of the analogue audio waveform.

Checks against the generated GO RTL pass for Covox word/byte writes, mixer
filtering/volume/saturation, and exact I2S words on the board's clock polarity.
The IDE SPI regression also confirms prefetch and exactly 5120 additional
clocks over 256 reads at delay index 8. No audio precision or filter changes
were made to disguise storage stalls.

The next candidate keeps 750 us for acceptance and shares one explicit SPI
guard across request collection, sector transfer, checksum and completion.
Owned transfer helpers reuse that guard; normal public calls retain their own
guard. Host tests verify identical wire data/reply order, lock coverage,
request collection, error/empty paths and writes. Its artifacts are under
`build/hdd-sector-batch/`. It sustained approximately 413–415 sectors/s at
750 us, and the user reported it was almost good but still needed more speed.

The next candidate reduces physical Sega-pad scanning from the normal 5 ms
minimum interval to 20 ms during UKNC HDD activity, returning to normal after
the same 100 ms idle window used by the OLED gate. A complete scan has 976 us
of deliberate busy waits, excluding GPIO/software overhead. At the original
cadence this repeatedly interrupts APP from the higher-priority INPUT task.
USB input routing and wakeups are unchanged. The tradeoff is physical-pad
polling at about 50 Hz during HDD streaming. `test_sega_poll.py` checks identical
scan waveforms/decoding at the normal cadence, both ports, the streaming
interval and return to normal. Artifacts are in `build/hdd-input-budget/`.
This build sustains approximately **443 sectors/s at 750 us**, with no read
errors or watchdog resets in the capture. The user reported “running and sounds
fine.” The earlier menu correction was confirmed as “menu works great.”

## Validation and installation

- PlatformIO GO firmware build passes.
- `test_storage.py` passes the IDE CHS/LBA, multi-sector prefetch, writes,
  write-protection and EOF/invalid-address cases through the checked SPI bridge.
- Menu navigation and SD reboot/sync regressions pass.
- Packaging accepts the existing routed FPGA manifest; the KG1 differs from
  26103101 only in its name/build metadata. No FPGA reroute was needed.
- The complete original MCU flash was saved and verified before replacement.
- SD1 was backed up, updated, flushed, remounted read-only and verified. All
  27 saved switches and six picker paths were preserved, including HDD delay 0
  and `bappwd.img`. Other root files matched their original hashes.
- The serial listing confirms `mc0511;UKNC MC-0511;26103102`.

Raw logs and device-specific records are in `build/board/hdd-*.log`,
`build/install-26103102/install.json`, and `build/before-hdd-26103102/`.
Distribution hashes are in `bin/kg1/manifest.json`.

## Release and current board state

The original MCU UF2 was restored using `picotool load -v -x` and flash-verified.
A clean rebuild after removing the experiment matches the original binary:
`decececfe5fe3bca22e40609f51d575ef10777326989e9791d16710eb4fea243`.
At that rollback, the bundle contained this original UF2 and the renamed KG1. The watchdog resets
left SD initialization failing until a complete power cycle; the firmware's
normal reboot sync cannot run after a watchdog timeout.

After the user power-cycled the board, serial capture confirmed SD mounted
successfully, the boot menu loaded, and the configured TS-Conf autoload completed
all 98,304 ROM bytes. See `build/board/hdd-rollback-after-power-cycle.log`.

The distribution now contains the final MCU improvements with the OSD backlog
correction and the renamed KG1. Installation records identify exact binaries;
`build/board/firmware-install.json` tracks the most recently verified install.
The installed final SHA-256 is
`2200980c85ce42a11a027849818430e316b870b3ef89282c63d34d2c5002089f`;
see `build/hdd-input-budget/install.json`. Flash verification, SD mounting and
the configured TS-Conf autoload completed successfully. The user subsequently
selected UKNC and tested playback at 750 us; measurements are in
`build/hdd-input-budget/acceptance.log`.
The original UF2 remains available in `build/before-hdd-26103102/` for rollback.

The selected operating point is **750 us**, retaining Tang's distributed
sample pacing. Sector throughput is measured; good sound and responsive menus
are user observations. Video frame rate and analogue audio spectra were not
captured on GO. No FPGA bus clock, Covox sample precision or mixer filter was
changed during this investigation.
