; ---------------------------------------------------------------------------
; Hello World for the Apple I (MOS 6502, NMOS)
;
; Differences from src/hello.s (Chiplab) and c64/hello.s (C64):
;   - output goes through the Woz Monitor routine ECHO at $FFEF:
;     load the character into A, JSR $FFEF, it appears on screen
;   - the Apple I display uses 7-bit ASCII, but the Woz Monitor works
;     with bit 7 set, so we ORA #$80 every character (CR = $8D)
;   - UPPERCASE only: the Apple I has no lowercase characters
;   - the program ends with JMP $FF1F and goes back to the "\" prompt
;
; Build: make apple1  ->  build/hello-apple1.bin (loaded at $0280)
;                         build/hello-apple1.woz (text to type in Wozmon)
; ---------------------------------------------------------------------------

        .setcpu "6502"

ECHO    = $FFEF                 ; Woz Monitor: print the character in A
GETLINE = $FF1F                 ; Woz Monitor: back to the "\" prompt

        .segment "CODE"

start:
        ldx #0
print:
        lda message,x           ; next character
        beq done                ; 0 = end of string
        ora #$80                ; bit 7 high, as the Woz Monitor expects
        jsr ECHO                ; ECHO preserves X
        inx
        bne print               ; X never wraps to 0 here: always taken
done:
        jmp GETLINE             ; back to the Woz Monitor

        .segment "RODATA"

message:
        .byte $0D, "HELLO, WORLD!", $0D, 0
