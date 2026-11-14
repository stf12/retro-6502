# Chiplab 6502 – Programming model

2026-11-07 · Stefano Oliveri

## The diagram

**The program lives on the Mac: the board only has the 6502 and its pins.**

```
┌──────────────────────────┐        ┌────────────────────────────────────────────────┐
│         iMac M1          │        │                 Chiplab board                  │
│  script chiplab_run.py   │        │               no RAM, no ROM                   │
│                          │        │                                                │
│  ┌────────────────────┐  │        │  ┌─────────────────┐   A0–A15  ┌────────────┐  │
│  │   Memory 64 KB     │  │        │  │                 │ ◄──────── │            │  │
│  │ your hello.bin     │  │        │  │                 │   RWB     │            │  │
│  └────────────────────┘  │  USB   │  │ Microcontroller │ ◄──────── │   W65C02   │  │
│  ┌────────────────────┐  │ ◄────► │  │    firmware     │   D0–D7   │  the real  │  │
│  │  Console $F001     │  │        │  │ turns USB into  │ ◄───────► │    CPU     │  │
│  │ prints characters  │  │        │  │      pins       │ PHI2,RESB │  runs the  │  │
│  └────────────────────┘  │        │  │                 │ ────────► │    code    │  │
│  ┌────────────────────┐  │        │  └─────────────────┘           └────────────┘  │
│  │    Exit $F000      │  │        │                                                │
│  │ a write stops all  │  │        └────────────────────────────────────────────────┘
│  └────────────────────┘  │
└──────────────────────────┘
```

The 6502 talks only through its pins: the microcontroller turns them into USB messages, and the Mac answers as if it were the memory. The RWB pin tells the microcontroller the direction of each cycle: high = the 6502 reads, low = it writes.

## Two clarifications

1. **The microcontroller does not read the program.** The program never leaves the Mac: it is a 64 KB `bytearray` inside the Python script. The microcontroller doesn't know a program exists: it reports to the Mac what happens on the 6502's pins and carries out its commands.
2. **It advances one clock cycle at a time, not one instruction.** The microcontroller generates the clock (PHI2) one pulse at a time. `LDA message,X` takes 4 cycles, so 4 round trips with the Mac.

In practice the Mac acts as the 6502's RAM and ROM, connected by a very long "cable": USB.

## What the Python script does, cycle by cycle

Each clock cycle is an exchange of serial messages at 115200 baud; here is a read:

| # | From → to | Message | Meaning |
| --- | --- | --- | --- |
| 1 | Mac → board | `step` | "give one clock pulse" |
| 2 | board → Mac | `a=0x8002 r=1` | the 6502 puts $8002 on the address bus and wants to read (RWB high) |
| 3 | Mac → board | `d189` | the script looks up `memory[$8002]` = $BD (189) and sends it |
| 4 | board → 6502 | pins D0–D7 | the microcontroller puts $BD on the data bus and the 6502 reads it as if from a ROM |

If the 6502 **writes** (`r=0`), i.e. with RWB low, step 2 brings for example `a=0xF001 r=0 d=0x48`. The script stores the byte in its memory; if the address is `$F001` it prints the character, if it is `$F000` it stops.

At startup the script does two things:

- sends `info` to check that the board is on the other end (answer `6502_0.1`);
- sends `reset`, which pulls the 6502's RESB pin low for a few cycles.

Then it repeats the cycle up to 2000 times, or until the program writes to `$F000`.

## Why it is built this way

For studying the chip it is perfect: you see every bus access and can pause indefinitely between one cycle and the next, because the W65C02 is fully static. You invent the "memory" in Python: with a few lines in the script you add more special addresses, such as a keyboard or a timer.

The price is speed: about 170 cycles per second, measured as 5000 cycles in 30 s, against the million of a real 1 MHz computer.
