#!/usr/bin/env python3
"""Run an Apple I program in the terminal, without ROMs or MAME.

Uses py65 (already in the project's .venv) as the 6502 and fakes just
the two Woz Monitor entry points our programs use:

    $FFEF  ECHO     prints the character in A (bit 7 is ignored)
    $FF1F  GETLINE  "back to the monitor": the run stops here

It is a quick check of the program logic, not a full Apple I emulator:
for the real thing (Woz Monitor, screen, keyboard) use `make apple1-run`.

Usage: apple1_sim.py build/hello-apple1.bin [--addr 0x280] [--max-steps N]
"""
import argparse
import sys

from py65.devices.mpu6502 import MPU

ECHO, GETLINE = 0xFFEF, 0xFF1F


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("binary")
    ap.add_argument("--addr", type=lambda s: int(s, 0), default=0x0280)
    ap.add_argument("--max-steps", type=int, default=1_000_000)
    args = ap.parse_args()

    mpu = MPU()
    data = open(args.binary, "rb").read()
    mpu.memory[args.addr:args.addr + len(data)] = list(data)
    mpu.pc = args.addr

    for _ in range(args.max_steps):
        if mpu.pc == ECHO:
            ch = mpu.a & 0x7F
            sys.stdout.write("\n" if ch == 0x0D else chr(ch))
            sys.stdout.flush()
            # emulate RTS: pull the return address pushed by JSR
            lo = mpu.memory[0x100 + ((mpu.sp + 1) & 0xFF)]
            hi = mpu.memory[0x100 + ((mpu.sp + 2) & 0xFF)]
            mpu.sp = (mpu.sp + 2) & 0xFF
            mpu.pc = ((hi << 8) | lo) + 1
            continue
        if mpu.pc == GETLINE:
            print(f"\n[back to Woz Monitor after {mpu.processorCycles} cycles]")
            return 0
        mpu.step()

    print(f"\n[stopped: no return to the monitor after {args.max_steps} steps, "
          f"PC=${mpu.pc:04X}]", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
