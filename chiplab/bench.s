; ---------------------------------------------------------------------------
; bench.s - speed test for the Chiplab board
;
; An endless loop that never stops by itself: run it for a fixed number of
; cycles and time it, before and after a firmware change:
;
;     time make run PROG=bench CYCLES=5000
;
; cycles per second = 5000 / the "total" seconds that time prints
; (a fraction of a second of it is Python and make starting up).
; ---------------------------------------------------------------------------

        .setcpu "65C02"

        .segment "CODE"

reset:
        ldx #0
loop:
        inx                     ; 2 cycles
        stx $0200               ; 4 cycles: a write, so writes are measured too
        bra loop                ; 3 cycles

nmi_irq:
        rti

        .segment "VECTORS"
        .word nmi_irq           ; NMI
        .word reset             ; RESET
        .word nmi_irq           ; IRQ/BRK
