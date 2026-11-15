"""
asm_trace.py - disassembled bus trace for chiplab_run.py (--trace-asm).

The W65C02 drives its SYNC pin high in the cycle where it fetches an opcode,
and the board reports it as sync=1. At that moment the host already holds
all the bytes of the instruction in its memory image, so it can disassemble
it at once. Every other bus access until the next opcode fetch (operand
reads are skipped, data reads and writes, stack, dummy cycles) belongs to
that instruction and is shown on the same line:

  cycle  address   label        bytes     instruction                bus
     11  $8002     print        BD 10 80  LDA $8010,X  ; message     R $8010=$48
     15  $8005                  F0 06     BEQ $800D  ; done
     17  $8007                  8D 01 F0  STA $F001                  W $F001<-$48 'H'

Labels come from the ld65 label file (-Ln, VICE format: "al 008002 .print"),
found next to the image (build/hello.bin -> build/hello.lbl).
Disassembly uses py65 (pip install py65).
"""
import os
import re
import sys

RESET_VECTOR_HI = 0xFFFD   # last byte the 6502 reads before its first opcode
MAX_BUS = 6          # bus accesses shown per instruction line
NEAR = 64            # data access up to this far after a label: "label+n"
NO_SYNC_LIMIT = 64   # cycles after the reset vector without sync=1 -> give up


def load_labels(path):
    """ld65 -Ln file -> {address: 'name1, name2'}; missing file -> {}."""
    labels = {}
    if not path or not os.path.exists(path):
        return labels
    for line in open(path):
        parts = line.split()
        if len(parts) == 3 and parts[0] == "al":
            addr = int(parts[1], 16)
            name = parts[2].lstrip(".")
            if name.startswith("__"):
                continue                    # linker internals
            names = labels.get(addr, "").split(", ") if addr in labels else []
            if name not in names:           # -g lists exported names twice
                labels[addr] = ", ".join(names + [name])
    return labels


class WrapMemory:
    """The 64 KB image seen as a ring, like the 6502 does: $FFFF + 1 = $0000."""
    def __init__(self, mem):
        self.mem = mem

    def __getitem__(self, addr):
        return self.mem[addr & 0xFFFF]


class AsmTracer:
    def __init__(self, mem, labels, out=sys.stderr):
        try:
            from py65.devices.mpu65c02 import MPU
            from py65.disassembler import Disassembler
        except ImportError:
            sys.exit("--trace-asm needs py65: .venv/bin/pip install py65")
        self.mem = mem
        self.labels = labels
        self.out = out
        self.dis = Disassembler(MPU(memory=WrapMemory(mem)))
        self.current = None     # instruction being collected
        self.seen_sync = False
        self.booted = False     # True once the reset vector has been read
        self.boot_cycle = 0
        self.gave_up = False
        self.reset_bus = []     # accesses before the first opcode fetch
        print(f"{'cycle':>6}  {'address':8}  {'label':12} {'bytes':9} "
              f"{'instruction':26} bus", file=out)

    # -- called by chiplab_run.py for every bus cycle ------------------------
    def cycle(self, n, addr, is_read, value, sync):
        """value = byte read by the 6502, or byte it wrote."""
        if self.gave_up:
            kind = "R" if is_read else "W"
            arrow = "->" if is_read else "<-"
            print(f"{n:6d}  {kind} ${addr:04X} {arrow} ${value:02X}", file=self.out)
            return
        if not self.booted:
            # Reset sequence: the 6502 may still finish the previous program's
            # cycles (with SYNC high) and does dummy reads such as $FFFF.
            # Nothing is an instruction until the reset vector has been read.
            self.reset_bus.append(self.access(addr, is_read, value))
            if is_read and addr == RESET_VECTOR_HI:
                self.booted = True
                self.boot_cycle = n
            return
        if is_read and sync:
            self.flush()
            self.seen_sync = True
            self.start(n, addr)
            return
        if self.current is None:
            self.reset_bus.append(self.access(addr, is_read, value))
            if not self.seen_sync and n - self.boot_cycle >= NO_SYNC_LIMIT:
                self.give_up(n)
            return
        if is_read and addr in self.current["fetch"]:
            self.current["fetch"].discard(addr)     # operand byte: already shown
            return
        self.current["bus"].append(self.access(addr, is_read, value))

    def flush(self):
        """Print the instruction collected so far (call at the end too)."""
        if self.reset_bus and not self.seen_sync:
            self.line(None, None, "", "", "(reset sequence)", self.reset_bus)
            self.reset_bus = []
        c = self.current
        if c is None:
            return
        self.line(c["cycle"], c["addr"], c["bytes"], c["text"], None, c["bus"])
        self.current = None

    # -- internals -----------------------------------------------------------
    def start(self, n, addr):
        length, text = self.dis.instruction_at(addr)
        text = re.sub(r"\$([0-9a-f]+)", lambda m: "$" + m.group(1).upper(), text)
        target = re.search(r"\$([0-9A-F]{4})\b", text)
        if target:
            name = self.near_label(int(target.group(1), 16))
            if name:
                text += f"  ; {name}"
        raw = " ".join(f"{self.mem[(addr + i) & 0xFFFF]:02X}" for i in range(length))
        self.current = {
            "cycle": n, "addr": addr, "bytes": raw, "text": text, "bus": [],
            "fetch": {(addr + i) & 0xFFFF for i in range(1, length)},
        }

    def near_label(self, addr):
        """'name' for a labelled address, 'name+n' just after one, else None."""
        for back in range(NEAR + 1):
            name = self.labels.get(addr - back)
            if name:
                name = name.split(", ")[0]
                return name if back == 0 else f"{name}+{back}"
        return None

    def access(self, addr, is_read, value):
        name = self.near_label(addr)
        where = f"${addr:04X}" + (f"({name})" if name else "")
        if is_read:
            return f"R {where}=${value:02X}"
        text = f"W {where}<-${value:02X}"
        if 32 <= value < 127:
            text += f" '{chr(value)}'"
        return text

    def line(self, n, addr, raw, text, note, bus):
        cyc = f"{n:6d}" if n is not None else " " * 6
        adr = f"${addr:04X}" if addr is not None else ""
        label = self.labels.get(addr, "") if addr is not None else ""
        instr = note if note else text
        limit = len(bus) if note else MAX_BUS     # the reset line shows everything
        shown = bus[:limit] + ([f"+{len(bus) - limit} more"] if len(bus) > limit else [])
        print(f"{cyc}  {adr:8}  {label[:12]:12} {raw:9} {instr:26} {'  '.join(shown)}".rstrip(),
              file=self.out)

    def give_up(self, n):
        self.gave_up = True
        print(f"[chiplab] no SYNC after {n} cycles: this board does not report the "
              "6502's SYNC pin, so instructions cannot be found.\n"
              "[chiplab] showing the plain bus trace instead.", file=self.out)
        self.reset_bus = []
