; ---------------------------------------------------------------------------
; Hello World for the Commodore 64 (MOS 6510, NMOS 6502 family)
;
; Differences from src/hello.s (Chiplab, W65C02):
;   - no 65C02 instructions: BRA -> JMP (or a branch that is always taken)
;   - output goes through the KERNAL routine CHROUT at $FFD2:
;     load the character into A, JSR $FFD2, it appears on screen
;   - the program ends with RTS and goes back to the BASIC "READY." prompt
;
; Build: make c64  ->  build/hello-c64.prg
; The linker adds a BASIC line "SYS 2061", so on the C64 you just type RUN.
; ---------------------------------------------------------------------------

        .setcpu "6502"

CHROUT  = $FFD2                 ; KERNAL: print the character in A

        .segment "CODE"

start:
        ldx #0
print:
        lda message,x           ; next character
        beq done                ; 0 = end of string
        jsr CHROUT              ; KERNAL prints it (A, X, Y are preserved)
        inx
        bne print               ; X never wraps to 0 here: always taken
done:
        rts                     ; back to BASIC

        .segment "RODATA"

; With -t c64, ca65 converts ASCII to PETSCII: lowercase letters in the
; source show as UPPERCASE on the C64's standard screen.
message:
        .byte "hello, world!", $0D, 0
