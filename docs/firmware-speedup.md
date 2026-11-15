# Chiplab firmware: making the board ~3x faster

This note records how we rebuilt and changed the firmware of the ATmega32U4
on the Chiplab 6502 board (EmulationOnline "Chiplab – 6502 controller V2"),
what we changed, how we measured it, and how to recover the board if an
upload goes wrong.

**Result: 174 → 495 clock cycles per second (2.8x), with no change to the
host protocol.**

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

## The changes

All changes are in `firmware/6502_pcb/6502_pcb.ino`, marked `retro-6502:`.
The serial protocol is unchanged, so `chiplab_run.py` needs no change.

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

## Measurement

`chiplab/bench.s` is an endless loop of reads and a write
(`inx`, `stx $0200`, `bra`). It is timed over a fixed number of cycles:

```bash
time make run PROG=bench CYCLES=5000
```

| Firmware | 5000 cycles | Cycles per second | Time per cycle |
|---|---|---|---|
| Original (rebuilt) | 28.8 s | 174 | 5.8 ms |
| Shorter waits, bus released | 10.1 s | **495** | 2.0 ms |

Each figure includes about half a second of Python and make startup.
Hello World and the calculator give the same results as before.

## Recovery: when the board does not come back after an upload

It happened once: a complete and correct upload (verified later by reading
the flash back), after which the board did not appear on USB at all, not
even after unplugging the cable. The firmware was fine; the chip only
needed a real reset.

With the Caterina bootloader:

- at **power-on**, the firmware starts at once;
- after a **reset** on the RESET pin, the bootloader stays active for about
  8 seconds before starting the firmware.

The 6-pin ISP header next to the USB connector has, in the base board
schematic (`base32u4`, J2): 1 GND, 2 Level, 3 SCK, 4 MOSI, 5 MISO, 6 RESET.
GND and RESET are the **two end pins**, so tapping them together resets the
chip whichever way the board is turned. This worked on the V2 board. Use a
female–female jumper wire and avoid touching pin 2 (supply).

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

The ~2 ms left per cycle are mostly USB round trips: on a read cycle the Mac
sends `step`, waits for the answer, sends the data byte and waits again.
The next improvements are in the protocol, and need changes on both sides:

- send the data byte together with the next `step`, one round trip per cycle;
- let the firmware run several cycles before reporting;
- keep a copy of the program's memory pages in the microcontroller's RAM
  (about 1.2 KB is free).
