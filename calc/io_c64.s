; ---------------------------------------------------------------------------
; io_c64.s - calculator I/O for the Commodore 64, through the KERNAL ROM
;
; CHRIN  ($FFCF): the first call lets the user type and edit a whole screen
;                 line; RETURN ends it. Each call then returns the next
;                 character of that line, the last one is CR.
; CHROUT ($FFD2): prints the character in A.
; ---------------------------------------------------------------------------

CR      = $0D                   ; RETURN / end of line

        .export io_getc, io_putc, io_newline, io_quit

CHRIN   = $FFCF
CHROUT  = $FFD2

        .segment "BSS"
char:   .res 1

        .segment "CODE"

io_getc:
        txa                     ; keep X and Y: CHRIN may change them
        pha
        tya
        pha
        jsr CHRIN
        sta char
        pla
        tay
        pla
        tax
        lda char
        rts

io_putc = CHROUT                ; CHROUT already keeps X and Y

io_newline:
        lda #CR
        jmp CHROUT

io_quit:
        rts                     ; calc.s reset the stack to the SYS level:
                                ; this RTS returns to BASIC ("READY.")
