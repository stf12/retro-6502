# Chiplab board firmware

`6502_pcb/6502_pcb.ino` is the firmware of the ATmega32U4 on the Chiplab
6502 board, by EmulationOnline. It comes unmodified from
https://github.com/EmulationOnline/chiplab (`6502/firmware/6502_pcb/`,
repository at commit `a85ac3b`, 2026-05-18). It is redistributed under
the license in `LICENSE-EmulationOnline`: this product includes software
developed by EmulationOnline.

The board identifies as an **Arduino Micro** (`arduino:avr:micro`) with the
Caterina USB bootloader, so firmware is uploaded over the normal USB cable.

## Setup (once)

```bash
brew install arduino-cli avrdude
arduino-cli core install arduino:avr
```

If a compile fails with "bad CPU type", install Rosetta:
`softwareupdate --install-rosetta`.

## Commands

| Command | What it does |
|---|---|
| `make fw-build` | compiles the sketch into `build/firmware/` |
| `make fw-upload` | compiles and uploads it to the board |
| `make fw-backup` | reads the whole flash into `firmware/backup/flash-<date>.hex` |
| `make fw-restore FILE=firmware/backup/….hex` | writes a backup back |

`fw-restore` writes only the firmware part (`$0000-$6FFF`): the Caterina
bootloader at `$7000-$7FFF` is protected by the chip and stays as it is.

**Keep the original**: `firmware/backup/` is not committed (see
`.gitignore`). Keep a copy of the first backup, taken before any change,
somewhere safe outside the repository too.
