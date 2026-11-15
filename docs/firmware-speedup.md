# Chiplab firmware: making the board ~5x faster

This note records how we rebuilt and changed the firmware of the ATmega32U4
on the Chiplab 6502 board (EmulationOnline "Chiplab – 6502 controller V2"),
what we changed, how we measured it, and how to recover the board if an
upload goes wrong.

**Result: 174 → about 860 clock cycles per second (~5x), in two steps:**

1. shorter fixed waits in the firmware, same protocol: 174 → 495 cycles/s;
2. protocol 0.2, one USB round trip per cycle instead of two: 495 → ~860 cycles/s.

## Background

The board has no RAM and no ROM. The ATmega32U4 clocks the W65C02 one cycle
at a time and reports each bus access over USB; `tools/chiplab_run.py` on the
Mac acts as the memory (see `chiplab-6502-programming-model.md`).

One read cycle is a dialogue between the Mac and the board:

1. Mac → board: `step` — the firmware pulses the clock (PHI2), reads the
   address through two shift registers and the RWB pin, and answers
   `a=0x8002 r=1 sync=1`.
2. Mac → board: `d189` — the firmware drives the byte on D0–D7 and answers
   `d=0xBD`.

A write cycle needs only step 1. With the original firmware a cycle took
about 5.8 ms. Most of that was not USB: it was fixed waits in the firmware.

| Wait in the original firmware | Per read cycle |
|---|---|
| `hold_6502()`: `delayMicroseconds(1000)`, twice per clock pulse | 2 ms |
| `hold_6502()` again after putting the data byte on the bus | 1 ms |
| `shift_delay()`: 10 µs, 19 times to read one address | ~0.2 ms |
| **Total fixed waits** | **~3.2 ms** |

The comment in the original code says it: "1ms hold time = 1k transitions /
sec -> 500hz".

## The board and its toolchain

| Item | Value |
|---|---|
| Microcontroller | ATmega32U4, 16 MHz external crystal |
| Arduino board | Arduino Micro, `arduino:avr:micro` (USB VID:PID 2341:8037) |
| Bootloader | Caterina (`Micro-prod-firmware-2012-12-10.hex`), $7000–$7FFF |
| Fuses | lfuse 0xFF, hfuse 0xD8, efuse 0xCB |
| Lock bits | 0x0F: the bootloader cannot be overwritten by software |
| Firmware source | `firmware/6502_pcb/6502_pcb.ino`, from github.com/EmulationOnline/chiplab |
| Host tools | `arduino-cli` + `arduino:avr` core (compile, upload), Homebrew `avrdude` (backup, restore) |

Fuse values and the bootloader file come from the author's article on
flashing the bootloader (emulationonline.com/systems/chiplab/flashing-arduino-bootloader).

Commands (see `firmware/README.md`): `make fw-build`, `make fw-upload`,
`make fw-backup`, `make fw-restore FILE=…`.

On Apple Silicon, the Arduino `avr-gcc` and `avrdude` are Intel builds that
run under Rosetta 2, which macOS 28 will drop. Homebrew's `avrdude` is native.

## Step 0: back up and verify the toolchain

Before changing anything:

1. `make fw-backup` read the whole flash (firmware + bootloader) into
   `firmware/backup/`. Keep a copy outside the repository.
2. The unmodified sketch, compiled with `arduino-cli`, is exactly as big as
   the shipped firmware (5508 bytes) but not byte-identical: same code and
   data, laid out in a different order by the linker (for example, the same
   `CALL` instructions with different target addresses). The build
   environment differs, the program does not.
3. We uploaded the rebuilt original and checked `make run` and
   `make calc-run` before making any change.

## Step 1: shorter waits

All changes are in `firmware/6502_pcb/6502_pcb.ino`, marked `retro-6502:`.
In this step the serial protocol is unchanged, so `chiplab_run.py` needs no
change.

| Change | Before | After | Why it is safe |
|---|---|---|---|
| `hold_6502()` wait, at each clock edge and after driving the data bus | 1000 µs | 5 µs | The W65C02 is fully static and needs only nanoseconds between edges; each `digitalWrite` already takes microseconds. |
| `shift_delay()`, address shift registers | 10 µs | 2 µs | The shift registers need well under 1 µs per edge at 3.3 V. |
| Data bus after a read cycle | left as outputs until the next status read | set back to inputs right after the falling edge of PHI2 | Fixes a bus conflict, below. |

**The bus conflict.** On a read cycle the microcontroller drives D0–D7, and
the 6502 latches the byte on the falling edge of PHI2. The original firmware
switched the pins back to inputs only when it next read the data bus. If the
next cycle was a write, the 6502 and the microcontroller drove the bus at the
same time for about a millisecond. The fix releases the bus in
`clock_6502()`, right after the falling edge, when the 6502 has already
latched the byte. It adds 6 bytes to the firmware (5508 → 5514).

## Step 2: protocol 0.2, one round trip per cycle

After step 1, a cycle took about 2 ms, almost all of it USB round trips.
Each round trip costs about a millisecond whatever is sent, and a read cycle
needed two:

```
Mac → step        Mac ← a=0x8002 r=1 sync=1     (1st round trip)
Mac → d189        Mac ← d=0xBD                  (2nd round trip)
```

In the 0.1 protocol a `d` command was always followed by a `step`. The new
command `x<decimal>` sends the two together: drive the byte for the pending
read cycle, pulse the clock, report the next cycle.

Three read cycles of a program that starts with `LDA #$42` (bytes `A9 42`)
followed by `STA` (opcode `8D`):

```
Protocol 0.1: 6 round trips             Protocol 0.2: 3 round trips

Mac sends   Board answers               Mac sends   Board answers
step        a=0x8000 r=1 sync=1         step        a=0x8000 r=1 sync=1
d169        d=0xA9                      x169        a=0x8001 r=1 sync=0
step        a=0x8001 r=1 sync=0         x66         a=0x8002 r=1 sync=1
d66         d=0x42                      x141        (next cycle)
step        a=0x8002 r=1 sync=1
d141        d=0x8D
```

Each line is one round trip: the Mac sends a command and waits for the
answer. On the right, `x169` gives the 6502 the byte `$A9` it asked for at
`$8000` and, in the same round trip, returns the next cycle (`$8001`).

Write cycles carry no byte to deliver, so the next command is a plain
`step`.

`sync=1` marks the cycle in which the 6502 fetches an opcode, the first
byte of an instruction: here `$8000` (`LDA`) and `$8002` (`STA`), while
`$8001` is an operand. It comes from the W65C02's SYNC pin. `chiplab_run.py`
does not use it yet; it could stop on instruction boundaries, for
breakpoints or a disassembled trace.

**Why this works for any program.** Nothing is predicted or sent ahead.
Inside `x`, the firmware drives the byte, the 6502 latches it on the falling
edge of PHI2 and decides on its own what comes next (next byte, branch
target, write, stack access), and only then, after the rising edge, does the
firmware read the new address and report it. The bus cycles are exactly the
same as with the 0.1 protocol: the calculator test runs the same 24,729
cycles with either protocol, through branches, subroutines, keyboard reads
and its error handling.

Changes:

| Where | Change |
|---|---|
| firmware | new `x<decimal>` command; all 0.1 commands still work |
| firmware | `info` answers `6502_0.2` |
| firmware | status line built in a buffer and sent with one `Serial.write`, instead of up to eight `Serial.print` calls; same text |
| `tools/chiplab_run.py` | asks `info`; with `6502_0.2` it sends each read byte with the next step, with `6502_0.1` it keeps the old protocol |
| `tools/chiplab_run.py` | `--no-fast` forces the 0.1 protocol, to compare the two on the same firmware |

At start-up `chiplab_run.py` prints which protocol it uses, for example
`[chiplab] firmware 6502_0.2, 1 round trip per cycle`.

## Measurement

`chiplab/bench.s` is an endless loop of reads and a write
(`inx`, `stx $0200`, `bra`). It is timed over a fixed number of cycles:

```bash
time make run PROG=bench CYCLES=5000
time .venv/bin/python tools/chiplab_run.py --no-fast --cycles 5000 build/bench.bin
```

| Firmware and protocol | 5000 cycles | Cycles per second | Time per cycle | vs original |
|---|---|---|---|---|
| Original firmware (rebuilt), 0.1 | 28.8 s | 174 | 5.8 ms | 1x |
| Step 1: shorter waits, bus released, 0.1 | 10.1 s | 495 | 2.0 ms | 2.8x |
| Firmware 0.2, forced to the 0.1 protocol (`--no-fast`) | 9.6 s | 518 | 1.9 ms | 3.0x |
| **Firmware 0.2, protocol 0.2** | **5.8 s** | **~860** | **1.2 ms** | **~4.9x** |

Each figure includes about half a second of Python and make startup (and
in the last row the assembly of `bench.s`), so the real rates are slightly
higher.

What the numbers say:

- Sending the status line as one packet is worth only about 5% (495 → 518):
  the Arduino USB code already grouped the small writes well.
- The protocol is worth 1.65x (9.6 s → 5.8 s), close to the drop in round
  trips counted on a simulated board for the benchmark (3715 → 2000 per
  2000 cycles, 1.86x).

Hello World and the calculator give the same results as before, visibly
faster.

## Recovery: when the board does not come back after an upload

It happened once: a complete and correct upload (verified later by reading
the flash back), after which the board did not appear on USB at all, not
even after unplugging the cable. The firmware was fine; the chip only
needed a real reset.

With the Caterina bootloader:

- at **power-on**, the firmware starts at once;
- after a **reset** on the RESET pin, the bootloader stays active for about
  8 seconds before starting the firmware.

The 6-pin ISP header next to the USB connector follows J2 of the base board
schematic (`base32u4`). On the V2 board we checked it with a multimeter:

| Pin | Position | Signal | Measured |
|---|---|---|---|
| 1 | nearest the USB connector | GND | continuity with W65C02 pin 21 (VSS) |
| 2 | | Level = +5 V (USB VBUS) | 5.10 V |
| 3 | | SCK | 1.2 V (unused input, floating) |
| 4 | | MOSI | 1.2 V (unused input, floating) |
| 5 | | MISO | 1.2 V (unused input, floating) |
| 6 | farthest from the USB connector | RESET | 3.28 V; hundreds of kΩ to pin 2, so not a supply |

Voltages were measured with the board on USB, against W65C02 pin 21; the
W65C02 supply (pin 8) is 3.3 V. GND and RESET are the **two end pins**, so
tapping them together resets the chip. Use a female–female jumper wire and
avoid touching pin 2 (supply).

The ATmega32U4 runs at 3.3 V, but pin 2 carries 5 V. A 5 V Arduino used as
ISP programmer would drive SCK, MOSI and RESET above the chip's supply: use
a 3.3 V programmer or a level shifter. Tapping RESET to GND is always safe.

- **To just restart the firmware:** tap the two end pins together once,
  quickly, then move the wire away.
- **To restore a backup:** start the command below, tap the pins when it
  says so, and move the wire away at once. A wire left touching keeps
  resetting the chip, and avrdude fails with "initialization failed".

```bash
python3 tools/hex_app_only.py firmware/backup/<backup>.hex build/firmware-restore.hex
until ls /dev/cu.usbmodem* >/dev/null 2>&1; do sleep 0.2; done   # now tap RESET-GND
sleep 2
avrdude -p atmega32u4 -c avr109 -P "$(ls /dev/cu.usbmodem* | head -1)" \
  -U flash:w:build/firmware-restore.hex:i
```

Check first that no `/dev/cu.usbmodem*` port exists before the tap,
otherwise the script talks to the running firmware instead of the
bootloader. `hex_app_only.py` writes back only the firmware ($0000–$6FFF):
the bootloader area is protected by the lock bits.

`make fw-upload` now waits for the board to come back and prints these
instructions if it does not.

Useful checks:

- `system_profiler SPUSBHostDataType | grep -B3 -A12 -i micro` (on recent
  macOS `SPUSBDataType` returns nothing): Product ID **0x8037** is the
  firmware, **0x0037** the bootloader.
- After a backup, compare the firmware on the board with a build:
  `hex_app_only.py` both files, then `diff -q`.

## Where the remaining time goes, and next steps

A cycle now costs about 1.2 ms, and almost all of it is the single USB
round trip. One round trip per cycle is the floor of this design: to go
faster, the board must run **several cycles per round trip**, which means
doing some work without asking the Mac. Ideas, all needing changes on both
sides:

- keep a copy of the program's memory pages in the microcontroller's RAM
  (about 1.2 KB is free) and answer those reads locally, asking the Mac only
  for other addresses and reporting writes;
- let the firmware run a burst of cycles and send back a compressed trace.

Unlike protocol 0.2, these must handle cases where the copy can be wrong:
self-modifying code, memory-mapped I/O such as the keyboard at `$F004`, and
pages that were not copied.
