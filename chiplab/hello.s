; ---------------------------------------------------------------------------
; Hello World for the EmulationOnline Chiplab 6502 (W65C02)
;
; The Chiplab board has no RAM or ROM: your Mac *is* the memory. On every
; clock cycle the host script (tools/chiplab_run.py) sees the address bus,
; answers reads from this 64 KB image and records writes.
;
; By convention (implemented in chiplab_run.py, not in hardware):
;   $F001  CONSOLE  - any byte written here is printed as a character
;   $F000  EXIT     - any write here stops the run cleanly
; ---------------------------------------------------------------------------

        .setcpu "65C02"

CONSOLE = $F001
EXIT    = $F000

        .segment "CODE"         ; starts at $8000 (see chiplab.cfg)

reset:
        ldx #0
print:
        lda message,x           ; next character
        beq done                ; 0 = end of string
        sta CONSOLE             ; host prints it
        inx
        bra print               ; 65C02 branch-always
done:
;        sta EXIT                ; tell the host we're finished
halt:
        bra halt

nmi_irq:
        rti

message:
        .byte "Hello, World!", $0D, $0A, 0

        .segment "VECTORS"      ; $FFFA-$FFFF
        .word nmi_irq           ; NMI
        .word reset             ; RESET
        .word nmi_irq           ; IRQ/BRK
