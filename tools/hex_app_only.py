#!/usr/bin/env python3
"""
hex_app_only.py - keep only the application part of an ATmega32U4 flash dump.

A full flash read (make fw-backup) also contains the Caterina bootloader,
which lives in the last 4 KB ($7000-$7FFF). The chip protects that area:
the bootloader cannot overwrite itself, so writing it back would make
avrdude's verify fail. To restore a backup we write only the bytes below
$7000 (the firmware), and leave the bootloader as it is.

usage: hex_app_only.py in.hex out.hex [--limit 0x7000]
"""
import argparse


def read_hex(path):
    """Intel HEX -> {address: byte}. Supports record types 00, 01, 02, 04."""
    mem, base = {}, 0
    for n, line in enumerate(open(path), 1):
        line = line.strip()
        if not line:
            continue
        if not line.startswith(":"):
            raise SystemExit(f"{path}:{n}: not an Intel HEX line")
        raw = bytes.fromhex(line[1:])
        if sum(raw) & 0xFF:
            raise SystemExit(f"{path}:{n}: bad checksum")
        count, addr, rtype, data = raw[0], (raw[1] << 8) | raw[2], raw[3], raw[4:-1]
        if len(data) != count:
            raise SystemExit(f"{path}:{n}: wrong length")
        if rtype == 0x00:
            for i, b in enumerate(data):
                mem[base + addr + i] = b
        elif rtype == 0x01:
            break
        elif rtype == 0x02:
            base = ((data[0] << 8) | data[1]) << 4
        elif rtype == 0x04:
            base = ((data[0] << 8) | data[1]) << 16
        # other types (start address) are not needed for an AVR flash image
    return mem


def write_hex(path, mem):
    def rec(addr, rtype, data):
        raw = bytes([len(data), addr >> 8, addr & 0xFF, rtype]) + bytes(data)
        return ":" + (raw + bytes([(-sum(raw)) & 0xFF])).hex().upper() + "\n"

    out, addrs, i = [], sorted(mem), 0
    while i < len(addrs):                       # 16-byte records of consecutive bytes
        start, chunk = addrs[i], [mem[addrs[i]]]
        i += 1
        while i < len(addrs) and addrs[i] == start + len(chunk) and len(chunk) < 16:
            chunk.append(mem[addrs[i]])
            i += 1
        out.append(rec(start, 0x00, chunk))
    out.append(":00000001FF\n")
    open(path, "w").writelines(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("infile")
    ap.add_argument("outfile")
    ap.add_argument("--limit", type=lambda s: int(s, 0), default=0x7000,
                    help="first address of the bootloader (default 0x7000)")
    a = ap.parse_args()
    mem = read_hex(a.infile)
    app = {k: v for k, v in mem.items() if k < a.limit}
    boot = len(mem) - len(app)
    # Erased flash reads $FF. A full dump keeps the empty $FF area between the
    # end of the firmware and the bootloader: drop it, the chip erase before
    # writing leaves it $FF anyway.
    used = [k for k, v in app.items() if v != 0xFF]
    if not used:
        raise SystemExit("no firmware bytes below the bootloader: wrong file?")
    end = max(used)
    app = {k: v for k, v in app.items() if k <= end}
    write_hex(a.outfile, app)
    print(f"{a.outfile}: firmware ${min(app):04X}-${end:04X} "
          f"({end + 1} bytes), dropped {boot} bootloader bytes")


if __name__ == "__main__":
    main()