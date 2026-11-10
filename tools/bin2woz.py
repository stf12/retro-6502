#!/usr/bin/env python3
"""Convert a raw binary into Woz Monitor input for the Apple I.

The output is what you would type at the "\\" prompt:

    0280: A2 00 BD 92 02 F0 08 09
    0288: 80 20 EF FF E8 D0 F3 4C
    ...
    280R

Usage:
    bin2woz.py hello.bin                     # print the text
    bin2woz.py hello.bin -o hello.woz        # write it to a file
    bin2woz.py hello.bin --mame              # one line for MAME -autoboot_command
"""
import argparse
import sys


def woz_lines(data, addr, per_line=8, run=True):
    lines = []
    for i in range(0, len(data), per_line):
        chunk = data[i:i + per_line]
        lines.append(f"{addr + i:04X}: " + " ".join(f"{b:02X}" for b in chunk))
    if run:
        lines.append(f"{addr:X}R")
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("binary")
    ap.add_argument("--addr", type=lambda s: int(s, 0), default=0x0280,
                    help="load address (default 0x0280)")
    ap.add_argument("--no-run", action="store_true", help="omit the final 'xxxR' line")
    ap.add_argument("--mame", action="store_true",
                    help="emit a single string with \\n escapes for MAME -autoboot_command")
    ap.add_argument("-o", "--output", help="output file (default: stdout)")
    args = ap.parse_args()

    data = open(args.binary, "rb").read()
    if args.addr + len(data) > 0x1000:
        print(f"warning: program ends at ${args.addr + len(data) - 1:04X}, "
              "beyond the 4 KB of a stock Apple I", file=sys.stderr)

    lines = woz_lines(data, args.addr, run=not args.no_run)
    # Start with a CR so the monitor begins on a fresh line.
    text = ("\\n" + "\\n".join(lines) + "\\n") if args.mame else "\n".join(lines) + "\n"

    if args.output:
        with open(args.output, "w") as f:
            f.write(text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
