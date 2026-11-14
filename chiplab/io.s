; ---------------------------------------------------------------------------
; chiplab/io.s - basic I/O for the Chiplab board (W65C02)
;
; Shared by every program in apps/: keyboard, console, exit, plus the
; startup code and the reset vector.
;
; Memory-mapped "devices" emulated by tools/chiplab_run.py on the Mac:
;   $F001 CONSOLE  write: print a character
;   $F004 KEYBOARD read:  next character of the line typed on the Mac
;                         (the script waits for a whole line, then hands it
;                          over one character per read, ending with CR)
;   $F000 EXIT     write: stop the run
; ---------------------------------------------------------------------------

        .setcpu "65C02"
CR      = $0D                   ; RETURN / end of line
        .import main

        .export io_getc, io_putc, io_newline, io_quit

CONSOLE  = $F001
KEYBOARD = $F004
EXIT     = $F000

        .segment "CODE"

reset:                          ; the CPU starts here (RESET vector)
        ldx #$FF                ; stack at $01FF: needed for JSR/RTS
        txs
        cld                     ; binary arithmetic, not decimal (BCD)
        jmp main

io_getc:
        lda KEYBOARD
        rts

io_putc:
        cmp #CR                 ; the Mac terminal wants LF for a new line
        bne :+
        lda #$0A
:       sta CONSOLE
        rts

io_newline:
        lda #CR
        jmp io_putc

io_quit:
        sta EXIT
@halt:  bra @halt

nmi_irq:
        rti

        .segment "VECTORS"
        .word nmi_irq           ; NMI
        .word reset             ; RESET
        .word nmi_irq           ; IRQ/BRK
