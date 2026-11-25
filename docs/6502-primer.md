# 6502 Assembly Primer

A hands-on introduction to 6502 assembly language, written for this repository. Examples use the **ca65** assembler syntax and the Chiplab memory map, so they can be run directly with `chiplab_run.py`. Most of the material applies unchanged to the Commodore 64 and the Apple I.

## 1. The programmer's model

| Register | Size | Purpose |
|----------|------|---------|
| `A` | 8 bit | Accumulator: arithmetic, logic, most data movement |
| `X`, `Y` | 8 bit | Index registers, loop counters |
| `SP` | 8 bit | Stack pointer, the stack lives at `$0100-$01FF` |
| `PC` | 16 bit | Program counter |
| `P` | 8 bit | Status flags |

Status flags:

| Flag | Name | Meaning |
|------|------|---------|
| `N` | Negative | Bit 7 of the last result |
| `V` | Overflow | Signed overflow after `ADC` / `SBC` |
| `D` | Decimal | BCD arithmetic mode for `ADC` / `SBC` |
| `I` | Interrupt disable | Masks IRQ |
| `Z` | Zero | Last result was zero |
| `C` | Carry | Carry out of an add or shift; inverted borrow for subtraction |

Memory is 64 KB. Addresses are 16 bit and stored **little-endian** (low byte first). The first 256 bytes (`$0000-$00FF`) are the **zero page**: instructions that use it are shorter and faster, and it is the only place where indirect pointers can live.

Vectors (each is a 16-bit address stored in the last bytes of memory):

| Address | Vector |
|---------|--------|
| `$FFFA` | NMI |
| `$FFFC` | RESET: the CPU starts here |
| `$FFFE` | IRQ / BRK |

## 2. Number notation in ca65

```
lda #10        ; decimal 10
lda #$0A       ; hexadecimal
lda #%00001010 ; binary
lda #'A'       ; ASCII character
lda #<label    ; low byte of an address
lda #>label    ; high byte of an address
```

`#` means "immediate": the number itself. Without `#` it is an address.

## 3. Addressing modes

| Syntax | Mode | Notes |
|--------|------|-------|
| `LDA #$10` | Immediate | The value itself |
| `LDA $10` | Zero page | Address in `$00-$FF` |
| `LDA $10,X` | Zero page, X | Wraps inside the zero page |
| `LDA $1234` | Absolute | Full 16-bit address |
| `LDA $1234,X` | Absolute, X | Tables and arrays |
| `LDA $1234,Y` | Absolute, Y | Same, with Y |
| `LDA ($10,X)` | Indexed indirect | Pointer table in zero page |
| `LDA ($10),Y` | Indirect indexed | Pointer in zero page plus Y: the workhorse for buffers |
| `ASL A` | Accumulator | Operates on A |
| `BNE label` | Relative | Branches reach -128..+127 bytes |

## 4. Instruction groups

**Load and store**: `LDA LDX LDY STA STX STY`. Loads set `N` and `Z`; stores set nothing.

**Transfers**: `TAX TAY TXA TYA TSX TXS`.

**Arithmetic**: `ADC` (add with carry), `SBC` (subtract with borrow). Always prepare the carry:

```
clc            ; before ADC
adc #5

sec            ; before SBC
sbc #5
```

**Logic**: `AND ORA EOR`, and `BIT` (tests bits without changing A).

**Shifts and rotates**: `ASL` (shift left, bit 7 goes to `C`), `LSR` (shift right, bit 0 goes to `C`), `ROL`, `ROR` (rotate through `C`). `ASL` doubles a number, `LSR` halves it.

**Increment and decrement**: `INX INY DEX DEY INC DEC`.

**Compare**: `CMP CPX CPY` subtract without storing the result. After `CMP`: `Z` = equal, `C` = register >= operand (unsigned).

**Branches**: `BEQ BNE BCS BCC BMI BPL BVS BVC`. All are relative; for longer distances branch over a `JMP`.

**Flow control**: `JMP`, `JSR` (call), `RTS` (return), `RTI` (return from interrupt), `BRK`.

**Stack**: `PHA PLA PHP PLP`.

**Flags**: `CLC SEC CLI SEI CLD SED CLV`. `NOP` does nothing.

### W65C02 extras

The Chiplab board uses a WDC W65C02, which adds a few useful instructions to the original NMOS 6502. Enable them in ca65 with `.setcpu "65C02"`:

- `STZ` stores zero, `BRA` is an unconditional branch.
- `PHX PHY PLX PLY` push and pull X and Y.
- `INC A` and `DEC A` work directly on the accumulator.
- `LDA (zp)` is an indirect mode without Y.
- `TSB` and `TRB` set and reset bits in memory.

The C64's 6510 is an NMOS part and does **not** have these: code meant for both machines must avoid them.

## 5. Your first program

```
.setcpu "6502"

CONSOLE = $F001          ; Chiplab: write a byte here to print it
EXIT    = $F000          ; Chiplab: write here to stop the run

.segment "CODE"          ; segment names must match chiplab.cfg

reset:
    ldx #0
loop:
    lda msg,x            ; load next character
    beq done             ; zero terminator: finished
    sta CONSOLE
    inx
    bne loop             ; strings up to 255 characters
done:
    sta EXIT             ; A is 0 here
msg:
    .byte "Hello, 6502!", 10, 0

.segment "VECTORS"
    .word 0              ; NMI
    .word reset          ; RESET
    .word 0              ; IRQ
```

The pattern is the classic one: an index register, an indexed load, and a branch that uses the flags set by the previous instruction. Here `LDA` sets `Z` when it loads the terminator, and `BEQ` reacts to it.

## 6. Thinking in flags

Almost every instruction updates flags, and branches read them. Two rules save a lot of bugs:

1. The flags reflect the **last** instruction that touched them. Do not put an unrelated `LDA` between a `CMP` and its branch.
2. Stores, branches and jumps do not change flags.

Typical idioms:

```
    cmp #10
    bcc less         ; A < 10 (unsigned)
    beq equal        ; A == 10
                     ; otherwise A > 10

    lda value
    bmi negative     ; bit 7 set (signed negative)

    dex
    bne loop         ; loop until X reaches zero
```

## 7. Multi-byte arithmetic

The CPU is 8 bit, so larger numbers are processed byte by byte, propagating the carry.

16-bit addition:

```
    clc
    lda a_lo
    adc b_lo
    sta r_lo
    lda a_hi
    adc b_hi         ; carry from the low byte is added here
    sta r_hi
```

16-bit subtraction is identical with `SEC` and `SBC`. For a 16-bit increment:

```
    inc ptr
    bne :+
    inc ptr+1
:
```

## 8. Subroutines and the stack

`JSR` pushes the return address and jumps; `RTS` returns. The stack is only 256 bytes, so avoid deep recursion.

```
    lda #$3F
    jsr print_hex
    ...

; Prints A as two hexadecimal digits. Changes A and X.
print_hex:
    pha                  ; save the byte
    lsr
    lsr
    lsr
    lsr                  ; high nibble
    tax
    lda hexdigits,x
    sta CONSOLE
    pla
    and #$0F             ; low nibble
    tax
    lda hexdigits,x
    sta CONSOLE
    rts

hexdigits: .byte "0123456789ABCDEF"
```

Document in a comment which registers each routine changes. The 6502 has so few that this is the most important part of the "calling convention". Use `PHA` / `PLA` to preserve registers around calls when needed.

## 9. Pointers and buffers

Zero page pointers with `(zp),Y` let you walk memory anywhere:

```
ptr = $10                ; two bytes in zero page

    lda #<text
    sta ptr
    lda #>text
    sta ptr+1
    ldy #0
@next:
    lda (ptr),y
    beq @end
    sta CONSOLE
    iny
    bne @next
@end:
```

To pass the 256-byte limit of `Y`, increment the high byte of the pointer (`inc ptr+1`) and restart `Y` at zero.

## 10. Multiplication by shift and add

The 6502 has no multiply instruction. This routine computes `mcand * mplier` (8 x 8 bit) with a 16-bit result in `A` (high byte) and `mplier` (low byte):

```
; In:  mcand, mplier in zero page
; Out: A = high byte, mplier = low byte. Changes X.
mul8:
    lda #0
    ldx #8
    lsr mplier           ; first multiplier bit goes into C
@loop:
    bcc @noadd
    clc
    adc mcand
@noadd:
    ror                  ; shift the partial result right
    ror mplier           ; low bits collect in mplier, next bit goes to C
    dex
    bne @loop
    rts
```

Multiplying by a power of two is simply `ASL` repeated: three `ASL` multiply by 8.

## 11. Memory-mapped I/O on the Chiplab

The Mac answers every bus cycle, so devices are just addresses:

| Address | Device | Use |
|---------|--------|-----|
| `$F000` | EXIT | Any write ends the run |
| `$F001` | CONSOLE | Write a byte to print it |
| `$F004` | KEYBOARD | Read the next character of a typed line |
| `$F010-$F03F` | GFX chip | 320x200, 16 colours; see `docs/gfx-chip.md` |

Hardware registers must be accessed exactly as the device expects, and the CPU writes and reads in every cycle: a `LDA $F004` really performs a read on the bus. Avoid instructions that perform extra dummy accesses (for example read-modify-write instructions like `INC`) on device registers unless that is intended.

## 12. Debugging with the tools in this repository

- `chiplab_run.py --trace-asm --labels build/.../prog.lbl` shows one disassembled line per instruction, with your labels.
- `--trace` shows every bus cycle (address, read or write, data, SYNC).
- Assemble with `ca65 -g -l` and link with `ld65 -Ln prog.lbl` to get the listing and label files.

When something misbehaves, check in this order: wrong flag assumption, forgotten `CLC` / `SEC`, branch out of range, zero page clobbered by another routine, and `X` / `Y` changed by a subroutine.

## 13. Cycle counting

Each instruction takes 2 to 7 cycles. A few examples: `LDA #imm` 2, `LDA zp` 3, `LDA abs` 4, `STA abs` 4, `JSR` 6, `RTS` 6, taken branch 3 (4 if it crosses a page). This matters on a real machine (a C64 runs at about 1 MHz), while on the Chiplab board the USB link is the bottleneck (about 860 cycles per second).

## 14. Exercises

1. **Countdown**: print the digits `9` down to `0` on the console.
2. **String length**: write a routine that returns the length of a zero-terminated string in `A`.
3. **Uppercase**: read a line from `$F004` and print it in capital letters (hint: a lowercase ASCII letter has bit 5 set; `AND #%11011111`).
4. **Hex dump**: print 16 bytes of memory as hex using `print_hex`, separated by spaces.
5. **16-bit counter**: count from 0 to 1000, printing every 100.
6. **Decimal output**: print an unsigned 8-bit number in decimal (hint: repeated subtraction of 100, then 10).
7. **Fibonacci**: print the first Fibonacci numbers that fit in 16 bits (needs 16-bit addition and decimal conversion).
8. **Memory copy**: copy a block of 300 bytes using two zero page pointers.
9. **Graphics**: using `lib/gfx.inc`, draw a staircase of filled rectangles with growing colour index.
10. **Bit pattern**: draw an 8x8 sprite stored as 8 bytes, one pixel at a time, with `ASL` to test each bit through the carry.

## 15. Where to go next

- *Programming the 6502* by Rodnay Zaks and *6502 Assembly Language Programming* by Lance Leventhal are classics.
- The ca65 manual (cc65 documentation) for macros, scopes and segments.
- 6502.org: tutorials, tables of opcodes and cycle counts, and the forum.
- Visual6502 for the transistor-level view of what the chip really does each cycle.
