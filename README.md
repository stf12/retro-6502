# Chiplab 6502 — Hello World (macOS / Apple Silicon + VS Code)

## How this board works (read this first)

The Chiplab board has **no RAM and no ROM**. A microcontroller clocks the
W65C02 one cycle at a time and reports the bus over USB serial. Your Mac
runs `tools/chiplab_run.py`, which holds the 64 KB memory image, answers
every read and records every write.

So "printing" is a host-side convention defined in this project:

| Address | Name    | Effect                                   |
|---------|---------|------------------------------------------|
| `$F001` | CONSOLE | byte written → printed as a character    |
| `$F000` | EXIT    | any write → the run stops cleanly        |

Code lives at `$8000`, vectors at `$FFFA–$FFFF`.

## One-time setup (iMac M1)

```bash
# 1. Command-line tools (make, git, python3)
xcode-select --install

# 2. Homebrew (skip if you already have it) — https://brew.sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 3. 6502 assembler/linker (native arm64)
brew install cc65

# 4. VS Code + its `code` command
brew install --cask visual-studio-code
```

Then open this folder in VS Code (`code .`), accept the recommended
extensions, and in the terminal run once:

```bash
make setup      # creates .venv with pyserial
```

## Daily use

| VS Code                         | Terminal      | What it does                     |
|---------------------------------|---------------|----------------------------------|
| ⇧⌘B → *Chiplab: Build*          | `make`        | assemble + link `build/hello.bin`|
| Tasks → *Chiplab: Run on board* | `make run`    | upload/run on the board          |
| Tasks → *Run with bus trace*    | `make trace`  | same, printing every bus cycle   |
| Tasks → *List serial ports*     | `make ports`  | find the board's device name     |

The port is auto-detected (`/dev/cu.usbmodem…` or `/dev/cu.usbserial-…`).
Override with `make run PORT=/dev/cu.usbmodem1101`.
Other programs: put `foo.s` in `src/` and run `make run PROG=foo`.

Expected output:

```
[chiplab] /dev/cu.usbmodem1101
Hello, World!

[chiplab] program exited after ~200 cycles
```

## Commodore 64 version

`c64/hello.s` is the same program for the C64's 6510 (NMOS 6502):
`BRA` becomes an always-taken branch, output goes through the KERNAL
routine CHROUT (`JSR $FFD2`), and `RTS` returns to BASIC.

| VS Code                  | Terminal       | What it does                         |
|--------------------------|----------------|--------------------------------------|
| Tasks → *C64: Build .prg*| `make c64`     | builds `build/hello-c64.prg`         |
| Tasks → *C64: Run in VICE* | `make c64-run` | opens it in the VICE emulator      |

The .prg includes a BASIC line `SYS 2061`, so it starts with a plain `RUN`.

- **VICE**: `brew install --cask vice`. If `make c64-run` can't find it,
  drag `build/hello-c64.prg` onto the x64sc app, or run
  `make c64-run X64=/path/to/x64sc`.
- **Real C64 with Kung Fu Flash**: copy `hello-c64.prg` to the SD card,
  pick it in the Kung Fu Flash menu, and it loads and runs.
  On a plain disk: `LOAD"HELLO-C64",8` then `RUN`.

## Calculator (16-bit unsigned, Chiplab + C64)

Type `1234*56`, `300+45`, `1000/7` or `90-12` and press RETURN.
Spaces are allowed; an empty line ends the program. Range 0-65535.

| File | What it holds |
|---|---|
| `calc/calc.s` | main loop: reads the line, calls the operation, prints, handles errors |
| `calc/math16.s` | add, subtract, multiply (shift and add), divide (shift and subtract) |
| `calc/numio.s` | decimal text to number and back, string printing |
| `calc/io_chiplab.s` | Chiplab I/O: `$F004` keyboard, `$F001` console, `$F000` exit, reset vector |
| `calc/io_c64.s` | C64 I/O through the KERNAL: CHRIN `$FFCF`, CHROUT `$FFD2` |

The math and number files are identical on both machines; only the
`io_*.s` file changes. They use plain 6502 instructions only: the C64
build is assembled as 6502, so a 65C02-only instruction would be an error.

| VS Code | Terminal | What it does |
|---|---|---|
| Tasks → *Calc: Build (Chiplab + C64)* | `make calc calc-c64` | builds `build/calc.bin` and `build/calc-c64.prg` |
| Tasks → *Calc: Run on board* | `make calc-run` | runs on the Chiplab, no cycle limit (Ctrl-C stops) |
| Tasks → *Calc: Run in VICE* | `make calc-c64-run` | opens the C64 version in VICE |

On the Chiplab each line takes roughly 10-25 s (about 1,500-3,500 cycles
at ~170 cycles/s): turning numbers into text and back costs more than the
arithmetic itself. On the C64 it is instant.

## Notes

- Upstream's `serial_rom.py` uses `stty -F`, which is Linux-only, and stops
  after 200 cycles. `chiplab_run.py` uses pyserial instead, defaults to 2000
  cycles (`CYCLES=…`), and adds the console/exit ports.
- Each cycle is a USB round-trip, so expect hundreds-to-low-thousands of
  cycles per second — fine for learning, not for big loops.
- `build/hello.lst` shows the assembled bytes next to the source; handy with
  `make trace`.
- Source for the board: https://github.com/EmulationOnline/chiplab (6502/)
