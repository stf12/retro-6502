#!/usr/bin/env python3
"""Wrap a raw binary into a MAME Apple I snapshot (.snp).

MAME's apple1 driver loads a snapshot at startup with  -snapshot file.snp
Format (from MAME's apple1.cpp):  "LOAD:" + start address (2 bytes,
big-endian) + "DATA:" + the bytes. The load must fit in main RAM, or in
the 4 KB "BASIC RAM" at $E000-$EFFF.

Usage:
    bin2snp.py basic.bin  --addr 0xE000 -o build/basic.snp
    bin2snp.py build/hello-apple1.bin   -o build/hello-apple1.snp   (default $0280)
"""
import argparse
import sys


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("binary")
    ap.add_argument("--addr", type=lambda s: int(s, 0), default=0x0280)
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("--trim-last", action="store_true",
                    help="drop the last byte (MAME rejects loads ending at $EFFF)")
    a = ap.parse_args()

    data = open(a.binary, "rb").read()
    if a.trim_last:
        data = data[:-1]
    end = a.addr + len(data) - 1
    if a.addr >= 0xE000 and end > 0xEFFF:
        sys.exit(f"error: ${a.addr:04X}-${end:04X} does not fit in $E000-$EFFF")
    if a.addr == 0xE000 and len(data) not in (4095, 4096):
        print(f"warning: {len(data)} bytes; Apple I BASIC is exactly 4096", file=sys.stderr)

    with open(a.output, "wb") as f:
        f.write(b"LOAD:" + a.addr.to_bytes(2, "big") + b"DATA:" + data)
    print(f"{a.output}: ${a.addr:04X}-${end:04X} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
