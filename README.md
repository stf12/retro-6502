# retro-6502

6502 assembly for three machines: the EmulationOnline **Chiplab 6502**
board, the **Commodore 64** and the **Apple I** (in MAME). Built on macOS
(Apple Silicon) with cc65, from VS Code.

## Layout

```
chiplab/     Chiplab board: hello.s, gfxtest.s, window.s, chiplab.cfg (memory map),
             io.s, gfx.s, chiplab.mk
c64/         Commodore 64:  hello.s, io.s, c64.mk
apple1/      Apple I:       hello.s, apple1.cfg, apple1.mk, programs/
lib/         library interfaces shared by all machines: gfx.inc
apps/        programs for more than one machine
  calc/      16-bit calculator: portable code + calc.mk
tools/       host tools: chiplab_run.py, gfx_chip.py, Apple I converters and simulator
docs/        notes, e.g. the Chiplab programming model and the GFX chip
Makefile     includes the .mk files above; run make from this folder
```

Each machine folder holds its own `io.s`: the basic I/O (read a key,
print a character, quit) that every program in `apps/` links with.
A program in `apps/` contains only portable code, so moving it to another
machine means writing that machine's `io.s`, nothing else.

## Chiplab board: how it works (read this first)

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
make setup      # creates .venv with pyserial, py65 and pygame-ce
```

## Daily use

VS Code tasks are named *machine · program: action*, for example
*Chiplab · calc: run with disassembled trace*. A name ending in "…"
asks for input first.

| VS Code                         | Terminal      | What it does                     |
|---------------------------------|---------------|----------------------------------|
| ⇧⌘B → *Chiplab · hello: build*  | `make`        | assemble + link `build/hello.bin`|
| Tasks → *Chiplab · hello: run*  | `make run`    | upload/run on the board          |
| Tasks → *Chiplab · hello: run with bus trace* | `make trace`  | same, printing every bus cycle   |
| Tasks → *Chiplab · hello: run with disassembled trace* | `make trace-asm` | same, one disassembled line per instruction (see below) |
| Tasks → *Chiplab · board: list serial ports* | `make ports`  | find the board's device name     |

The port is auto-detected (`/dev/cu.usbmodem…` or `/dev/cu.usbserial-…`).
Override with `make run PORT=/dev/cu.usbmodem1101`.
Other programs: put `foo.s` in `chiplab/` and run `make run PROG=foo`.

### Disassembled trace

`make trace-asm` (and `make calc-trace-asm` for the calculator) runs the
program and writes one line per instruction to `build/<program>.asm-trace.txt`,
while the program's own output stays in the terminal. For any image already
built, `make trace-bin BIN=build/calc.bin CYCLES=0` writes the trace next to
it and opens it in VS Code; the task *Chiplab · any .bin: disassembled trace…*
asks for the file and the number of cycles.

```
 cycle  address   label        bytes     instruction                bus
  2327  $8154     @loop        4E 05 02  LSR $0205  ; num2+1        R $0205(num2+1)=$00  W $0205(num2+1)<-$00
  2332  $8157                  6E 04 02  ROR $0204  ; num2          R $0204(num2)=$05  W $0204(num2)<-$02
  2337  $815A                  90 10     BCC $816C  ; @shift
```

- Instruction starts come from the 6502's SYNC pin (`sync=1` from the board).
  On a board that does not report it, the trace falls back to one line per
  bus cycle after 64 cycles.
- The **bus** column lists the instruction's other accesses: data reads and
  writes, stack, dummy cycles. Operand bytes are not repeated.
- Names come from the ld65 label file next to the image (`build/hello.lbl`),
  as `name` or `name+offset`. Assemble with `-g` to include local labels.
- Disassembly uses py65 (`make setup` installs it; in an existing venv:
  `.venv/bin/pip install py65`). The code is in `tools/asm_trace.py`.

Expected output:

```
[chiplab] /dev/cu.usbmodem1101
Hello, World!

[chiplab] program exited after ~200 cycles
```

### Graphics

The Chiplab can also draw: `tools/gfx_chip.py` emulates a graphics chip
with a 320x200 screen and the 16 C64 colours, shown in a window on the
Mac. Programs use the graphics library: the interface is
[lib/gfx.inc](lib/gfx.inc), the Chiplab implementation `chiplab/gfx.s`.

```asm
        .include "gfx.inc"
        jsr gfx_init
        PAPER BLUE
        jsr clear_screen
        PEN YELLOW
        LINE 10, 20, 300, 150           ; macro: constant values
        lda radius                      ; computed values: store the
        sta gfx_r                       ; gfx_* variables yourself
        stz gfx_r+1
        jsr draw_circle
```

Parameters go in the `gfx_*` variables, 16 bit, low byte first; on the
Chiplab they are the chip's own registers, so nothing is copied. The
routines change only A, and leave the `gfx_*` variables as they are.
`lib/gfx.inc` lists every routine; the chip itself is described in
[docs/gfx-chip.md](docs/gfx-chip.md).

| VS Code | Terminal | What it draws |
|---|---|---|
| Tasks → *Chiplab · gfxtest: run* | `make run PROG=gfxtest CYCLES=0` | every routine: colours, lines, circles, XOR, clipping |
| Tasks → *Chiplab · window: run* | `make run PROG=window CYCLES=0` | a Macintosh Classic style window, its content clipped |

Add `GFX_PNG=build/screen.png` to save the final screen. The window opens
at the first access to the graphics, so text programs never open one, and
stays open after the program ends: close it or press Esc.

Single-file programs in `chiplab/` are linked with the library
(`build/chiplab/chiplab.lib`, made with `ar65`): ld65 takes only the
modules a program uses, so `hello.bin` gets no graphics code.

## Commodore 64 version

`c64/hello.s` is the same program for the C64's 6510 (NMOS 6502):
`BRA` becomes an always-taken branch, output goes through the KERNAL
routine CHROUT (`JSR $FFD2`), and `RTS` returns to BASIC.

| VS Code                  | Terminal       | What it does                         |
|--------------------------|----------------|--------------------------------------|
| Tasks → *C64 · hello: build* | `make c64`     | builds `build/hello-c64.prg`         |
| Tasks → *C64 · hello: run in VICE* | `make c64-run` | opens it in the VICE emulator      |

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
| `apps/calc/calc.s` | main loop: reads the line, calls the operation, prints, handles errors |
| `apps/calc/math16.s` | add, subtract, multiply (shift and add), divide (shift and subtract) |
| `apps/calc/numio.s` | decimal text to number and back, string printing |
| `chiplab/io.s` | Chiplab I/O: `$F004` keyboard, `$F001` console, `$F000` exit, reset vector |
| `c64/io.s` | C64 I/O through the KERNAL: CHRIN `$FFCF`, CHROUT `$FFD2` |

The files in `apps/calc/` are identical on both machines; only the
machine's `io.s` changes. They use plain 6502 instructions only: the C64
build is assembled as 6502, so a 65C02-only instruction would be an error.

| VS Code | Terminal | What it does |
|---|---|---|
| Tasks → *Chiplab · calc: build* | `make calc` | builds `build/calc.bin` |
| Tasks → *C64 · calc: build* | `make calc-c64` | builds `build/calc-c64.prg` |
| Tasks → *Chiplab · calc: run* | `make calc-run` | runs on the Chiplab, no cycle limit (Ctrl-C stops) |
| Tasks → *Chiplab · calc: run with disassembled trace* | `make calc-trace-asm` | same, trace in `build/calc.asm-trace.txt` |
| Tasks → *C64 · calc: run in VICE* | `make calc-c64-run` | opens the C64 version in VICE |

On the Chiplab each line takes roughly 10-25 s (about 1,500-3,500 cycles
at ~170 cycles/s): turning numbers into text and back costs more than the
arithmetic itself. On the C64 it is instant.

## Apple I version

`apple1/hello.s` is the same program for the Apple I (MOS 6502, NMOS).
It is loaded at `$0280`, prints through the Woz Monitor routine ECHO
(`JSR $FFEF`, character with bit 7 set) and returns to the `\` prompt
with `JMP $FF1F`. UPPERCASE only: the Apple I has no lowercase.

| VS Code                            | Terminal           | What it does |
|------------------------------------|--------------------|--------------|
| Tasks → *Apple I · hello: build* | `make apple1`      | builds `build/hello-apple1.bin` and `.woz`, prints the hex to type |
| Tasks → *Apple I · hello: run in terminal (quick check)* | `make apple1-sim`  | runs it in py65 with a fake ECHO: instant check, no ROMs |
| Tasks → *Apple I · hello: run in MAME* | `make apple1-run`  | starts MAME's Apple I and types the program into the Woz Monitor |
| —                                  | `make apple1-snap` | same, but loads it as a snapshot: starts instantly |

- `apple1-sim` needs py65 in the project venv: `.venv/bin/pip install py65`.
- **By hand** (MAME, POM1 or a real Apple I / replica): at the `\` prompt
  type the lines in `build/hello-apple1.woz`; the last line, `280R`,
  starts the program.
- `tools/bin2woz.py` works for any program: `python3 tools/bin2woz.py file.bin --addr 0x300`.

### MAME setup

- **Install**: `brew install mame` (skip if you already have it).
- **ROMs**: MAME does not include the Apple I firmware. Put the ROM sets,
  still zipped, in `~/Applications/mame/roms` (the default in `apple1/apple1.mk`):
  - `apple1.zip`: `apple-a1.a1`, `apple-a2.a2` (Woz Monitor), `s2513.d2` (character generator)
  - `a1cass.zip`: `apple-a3.3`, `apple-a4.4` (cassette interface card, fitted by default)

  Check with `mame -verifyroms apple1 -rompath ~/Applications/mame/roms`.
  A different folder: `make apple1-run MAME_ROMPATH=/your/roms/folder`.
  MAME's own default `rompath` is just `roms`, i.e. relative to the folder
  it is started from, so there is no global ROM folder to discover.
- **Keyboard**: by default MAME maps key *positions* to a US keyboard.
  On a British/International Mac keyboard `#` is Option+3, which reaches
  the Apple I as `3`; `"` is on Shift+'. Easiest fix: press **Tab** for
  MAME's menu and set *Keyboard Mode* to **Natural**.
- **Quitting**: the Makefile passes `-ui_active`, so **Esc** quits MAME.
  Otherwise close the window, or run `killall mame` from a terminal.

## Apple I Integer BASIC

Woz's original BASIC lives in the 4 KB of RAM at `$E000-$EFFF`.
Put the 4096-byte image at `apple1/basic.bin` (or pass `BASIC=path`).
The original, unpatched version ends with the bytes `0C E0`:
`tail -c 2 apple1/basic.bin | od -t x1`. One source is `images/basic.rom`
in https://github.com/jscrane/Apple1, whose `data/` folder also has
ready-to-type programs: copy them to `apple1/programs/`.

| VS Code                              | Terminal | What it does |
|--------------------------------------|----------|--------------|
| Tasks → *Apple I · BASIC: start* | `make basic-run` | loads BASIC and starts it (`>` prompt) |
| Tasks → *Apple I · BASIC: type in a program…* | `make basic-prog PROG=apple1/programs/HAMURABI.txt` | starts BASIC, types the listing, then `RUN` |
| Tasks → *Apple I · machine code: type in a program…* | `make woz-prog PROG=apple1/programs/life.txt RUN=2000` | types Woz Monitor hex and runs it (`microchess.txt`: `RUN=300`) |

How it works:

- `tools/bin2snp.py` wraps a binary into a MAME snapshot (`.snp`:
  `"LOAD:"` + big-endian start address + `"DATA:"` + bytes), which MAME
  loads at startup with `-snapshot`.
- MAME's apple1 snapshot loader has an off-by-one: a load that ends at
  `$EFFF` is rejected ("Snapshot can't fit in RAM"). So the snapshot holds
  `$E000-$EFFE` (`--trim-last`) and the last byte is typed in the Woz
  Monitor (`EFFF: E0`) before `E000R`. The Monitor answers `EFFF: 00`,
  the value *before* the write: that is normal.
- `tools/txt2lua.py` turns a listing into a MAME Lua script
  (`-autoboot_script`) that types it **one line at a time**. The Apple I
  keyboard latches a single character: while BASIC is busy storing a line
  and printing to the slow screen (~60 characters/s), a fast typist loses
  the next character (`5030` becomes `030`). The script waits until a line
  has been typed, then pauses `LINE_DELAY` frames (default 40, 60 = 1 s).
  If characters still get lost: `make basic-prog ... LINE_DELAY=60`.
- Long programs take minutes to type in, just like on the real machine.

Integer BASIC cheat sheet:

| Command | Effect |
|---|---|
| `LIST 1,100` | lists lines 1 to 100 (a comma, not a dash) |
| `LIST 5020` | lists one line |
| `40` | a line number alone deletes that line |
| `CALL -256` | back to the Woz Monitor (`$FF00`); the program stays in memory |
| `E2B3R` | (from the Monitor) warm start: back to BASIC, program kept |
| `E000R` | (from the Monitor) cold start: BASIC from scratch, program erased |

Integers only (-32767..32767), uppercase only; `#` and `<>` both mean
"not equal".

## Notes

- Upstream's `serial_rom.py` uses `stty -F`, which is Linux-only, and stops
  after 200 cycles. `chiplab_run.py` uses pyserial instead, defaults to 2000
  cycles (`CYCLES=…`), and adds the console/exit ports.
- Each cycle is a USB round-trip plus fixed delays in the board firmware:
  about 170 cycles per second, measured — fine for learning, not for big loops.
- `build/hello.lst` shows the assembled bytes next to the source; handy with
  `make trace`.
- Source for the board: https://github.com/EmulationOnline/chiplab (6502/)
