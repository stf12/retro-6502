; ---------------------------------------------------------------------------
; numio.s - read and print 16-bit unsigned decimal numbers
;
; Input is read one character at a time with io_getc. The parser keeps
; one character of look-ahead in `ch`: it is always the NEXT character
; not yet used.
; ---------------------------------------------------------------------------

        .include "calc.inc"
        .import err_syntax, err_too_big ; error handlers in calc.s

        .export val, ch
        .export read_u16, print_u16, skip_spaces, print_str

        .segment "BSS"
val:    .res 2                  ; the number being read or printed
tmp:    .res 2
ch:     .res 1                  ; look-ahead character
digit:  .res 1
started:.res 1                  ; 1 once a non-zero digit was printed

        .segment "CODE"

; ---------------------------------------------------------------------------
; skip_spaces: read past any spaces; on return `ch` is not a space
; ---------------------------------------------------------------------------
skip_spaces:
        lda ch
        cmp #' '
        bne @done
        jsr io_getc
        sta ch
        jmp skip_spaces
@done:
        rts

; ---------------------------------------------------------------------------
; read_u16: parse a decimal number starting at `ch` into `val`
; Each digit: val = val * 10 + digit.
; Errors jump to err_syntax (no digit) or err_too_big (> 65535).
; ---------------------------------------------------------------------------
read_u16:
        jsr skip_spaces
        lda ch
        sec
        sbc #'0'                ; '0'..'9' -> 0..9, anything else -> >= 10
        cmp #10                 ; (characters below '0' wrap around to 246+)
        bcc @first
        jmp err_syntax          ; a number was expected here
@first:
        lda #0
        sta val
        sta val+1
@loop:
        lda ch
        sec
        sbc #'0'
        cmp #10
        bcs @done               ; not a digit: the number is over
        sta digit
        jsr mul10               ; val = val * 10
        clc
        lda val                 ; val = val + digit
        adc digit
        sta val
        bcc @nocarry
        inc val+1
        beq @big                ; $FFFF + 1 wrapped to 0: too big
@nocarry:
        jsr io_getc             ; next character
        sta ch
        jmp @loop
@done:
        rts
@big:
        jmp err_too_big

; val = val * 10  as  (val * 2) + (val * 8), using only shifts and one add
mul10:
        asl val                 ; * 2
        rol val+1
        bcs @big
        lda val
        sta tmp
        lda val+1
        sta tmp+1               ; tmp = val * 2
        asl val                 ; * 4
        rol val+1
        bcs @big
        asl val                 ; * 8
        rol val+1
        bcs @big
        clc
        lda val                 ; val*8 + val*2 = val*10
        adc tmp
        sta val
        lda val+1
        adc tmp+1
        sta val+1
        bcs @big
        rts
@big:
        jmp err_too_big

; ---------------------------------------------------------------------------
; print_u16: print `val` in decimal, without leading zeros (val is destroyed)
; For 10000, 1000, 100, 10: count how many times it can be subtracted.
; That count is the digit. What is left at the end is the units digit.
; ---------------------------------------------------------------------------
print_u16:
        ldx #0                  ; index into the powers-of-ten table
        stx started
@digit:
        ldy #'0'                ; digit counter, kept directly as a character
@sub:
        lda val                 ; try val - 10^n
        sec
        sbc pow10_lo,x
        sta tmp
        lda val+1
        sbc pow10_hi,x
        bcc @got                ; would go negative: digit complete
        sta val+1
        lda tmp
        sta val
        iny                     ; one more 10^n fits
        jmp @sub
@got:
        sty digit
        cpy #'0'
        bne @print              ; non-zero digit: always print
        lda started
        beq @next               ; a zero before any other digit: skip it
@print:
        lda digit
        jsr io_putc             ; (io_putc keeps X)
        lda #1
        sta started
@next:
        inx
        cpx #4
        bne @digit
        lda val                 ; units: 0..9 left in the low byte
        clc
        adc #'0'
        jmp io_putc             ; always printed, so 0 shows as "0"

pow10_lo: .byte <10000, <1000, <100, <10
pow10_hi: .byte >10000, >1000, >100, >10

; ---------------------------------------------------------------------------
; print_str: print the zero-terminated string at A (low) / X (high)
; ---------------------------------------------------------------------------
print_str:
        sta ptr
        stx ptr+1
        ldy #0
@loop:
        lda (ptr),y
        beq @done
        jsr io_putc             ; (io_putc keeps Y)
        iny
        bne @loop
@done:
        rts
