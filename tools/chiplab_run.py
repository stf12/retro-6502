#!/usr/bin/env python3
"""
chiplab_run.py - run a 64 KB memory image on the EmulationOnline Chiplab 6502.

macOS-friendly rewrite of upstream 6502/host/serial_rom.py (which uses the
Linux-only `stty -F`). Uses pyserial, auto-detects the board, and adds
memory-mapped "devices" handled on the host side:

  $F001  CONSOLE  - bytes written are printed as characters
  $F004  KEYBOARD - each read returns the next character of a line typed
                    on the Mac (waits for a line; the line ends with CR $0D)
  $F000  EXIT     - a write here ends the run

Protocol (from the board firmware, newline-terminated text over USB):
  info  -> "6502_0.1" (original) or "6502_0.2" (retro-6502 firmware)
  reset -> "reset."
  step  -> "a=0x8000 r=1 sync=1"      (reads)
           "a=0xF001 r=0 d=0x48 ..."  (writes)
  d<decimal> -> "d=0x48"              (put a byte on the data bus)
  x<decimal> -> like step             (0.2 only: d<decimal> + step in one)

With firmware 0.2, the byte for a read cycle is sent together with the next
step ("x189"): one USB round trip per cycle instead of two. --no-fast forces
the 0.1 protocol, to compare the two on the same firmware.
"""
import argparse
import sys

import serial
import serial.tools.list_ports

CONSOLE = 0xF001
KEYBOARD = 0xF004
EXIT = 0xF000

_keys = []


def next_key():
    """Next input character for the 6502: a whole line is read first."""
    if not _keys:
        try:
            line = input()
        except EOFError:
            line = ""
        _keys.extend(b if b < 128 else ord("?") for b in line.encode("utf-8"))
        _keys.append(0x0D)
    return _keys.pop(0)


def find_port():
    ports = list(serial.tools.list_ports.comports())
    # Board shows up as /dev/cu.usbmodem* (native USB) or cu.usbserial-*.
    cands = [p.device for p in ports
             if "usbmodem" in p.device or "usbserial" in p.device
             or "ttyACM" in p.device or "ttyUSB" in p.device]
    cands = [c for c in cands if "/tty." not in c] or cands  # prefer cu.* on macOS
    if not cands:
        sys.exit("No Chiplab board found. Is it plugged in? Try `make ports`.")
    if len(cands) > 1:
        print(f"Several ports found, using {cands[0]} (others: {cands[1:]})",
              file=sys.stderr)
    return cands[0]


class Board:
    def __init__(self, port, trace=False):
        self.s = serial.Serial(port, 115200, timeout=3)
        self.trace = trace
        self.fast = False       # firmware 0.2: send read data with next step
        self.pending = None     # byte for the last read cycle, not sent yet

    def cmd(self, text):
        self.s.write((text + "\n").encode("ascii"))
        return self.readline()

    def readline(self):
        line = self.s.readline().decode("ascii", "replace").strip()
        if not line:
            sys.exit("Timeout waiting for the board.")
        return line

    def sync(self, allow_fast=True):
        # The board may print "pins setup"/"reset." etc. on connect: drain it.
        self.s.reset_input_buffer()
        for _ in range(5):
            version = self.cmd("info")
            if version in ("6502_0.1", "6502_0.2"):
                self.fast = allow_fast and version == "6502_0.2"
                mode = "1 round trip per cycle" if self.fast else "2 per read cycle"
                print(f"[chiplab] firmware {version}, {mode}", file=sys.stderr)
                return
        sys.exit("Board did not answer 'info' with 6502_0.1 or 6502_0.2.")

    def next_cycle(self):
        """Clock the 6502 once and return its status line."""
        if self.pending is not None:
            line = self.cmd(f"x{self.pending}")
            self.pending = None
            return line
        return self.cmd("step")

    def answer_read(self, value):
        """Give the 6502 the byte for the current read cycle."""
        if self.fast:
            self.pending = value        # travels with the next x command
        else:
            self.cmd(f"d{value}")


def parse_status(line):
    f = {}
    for part in line.split():
        k, _, v = part.partition("=")
        f[k] = int(v, 0)
    return f["a"], bool(f["r"]), f.get("d", 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image", help="64 KB binary (shorter images are zero-padded)")
    ap.add_argument("--port", default="auto")
    ap.add_argument("--cycles", type=int, default=2000,
                    help="stop after this many cycles; 0 = no limit")
    ap.add_argument("--trace", action="store_true", help="print every bus cycle")
    ap.add_argument("--no-fast", action="store_true",
                    help="use the original protocol even with firmware 0.2")
    a = ap.parse_args()

    mem = bytearray(open(a.image, "rb").read())
    if len(mem) > 0x10000:
        sys.exit("Image larger than 64 KB.")
    mem += bytes(0x10000 - len(mem))

    port = find_port() if a.port == "auto" else a.port
    print(f"[chiplab] {port}", file=sys.stderr)
    b = Board(port, a.trace)
    b.sync(allow_fast=not a.no_fast)

    # reset toggles the clock internally and prints "reset." last.
    b.s.write(b"reset\n")
    while b.readline() != "reset.":
        pass

    cycle = 0
    try:
        while a.cycles == 0 or cycle < a.cycles:
            if step(b, mem, cycle, a.trace):
                return
            cycle += 1
    except KeyboardInterrupt:
        print(f"\n[chiplab] interrupted after {cycle} cycles", file=sys.stderr)
        return
    print(f"\n[chiplab] stopped after {a.cycles} cycles (no write to $F000)",
          file=sys.stderr)


def step(b, mem, cycle, trace):
    """One clock cycle. Returns True when the program wrote to EXIT."""
    addr, is_read, data = parse_status(b.next_cycle())
    if is_read:
        val = next_key() if addr == KEYBOARD else mem[addr]
        if trace:
            print(f"{cycle:5d}  R ${addr:04X} -> ${val:02X}", file=sys.stderr)
        b.answer_read(val)
        return False
    if trace:
        print(f"{cycle:5d}  W ${addr:04X} <- ${data:02X}", file=sys.stderr)
    mem[addr] = data
    if addr == CONSOLE:
        sys.stdout.write(chr(data))
        sys.stdout.flush()
    elif addr == EXIT:
        print(f"\n[chiplab] program exited after {cycle + 1} cycles",
              file=sys.stderr)
        return True
    return False


if __name__ == "__main__":
    main()
