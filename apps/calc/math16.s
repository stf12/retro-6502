; ---------------------------------------------------------------------------
; math16.s - 16-bit unsigned arithmetic for the 6502
;
; Inputs:  num1, num2 (2 bytes each, little-endian)
; Outputs: res (2 bytes used, 4 reserved for the multiplication)
;          rem (remainder of the division)
;
; The 6502 ALU only adds and subtracts 8 bits at a time, so:
;   - add/sub work byte by byte, the carry links the low and high byte
;   - multiply = "shift and add"       (long multiplication, in binary)
;   - divide   = "shift and subtract"  (long division, in binary)
;
; Only plain 6502 instructions: the same code runs on the W65C02 (Chiplab)
; and on the 6510 (C64).
; ---------------------------------------------------------------------------

        .export num1, num2, res, rem
        .export add16, sub16, mul16, div16

        .segment "BSS"
num1:   .res 2
num2:   .res 2
res:    .res 4                  ; 32 bits: a 16x16 product needs them all
rem:    .res 2

        .segment "CODE"

; ---------------------------------------------------------------------------
; add16: res = num1 + num2
; Out: C=1 if the result does not fit in 16 bits (> 65535)
; ---------------------------------------------------------------------------
add16:
        clc                     ; no carry into the low byte
        lda num1
        adc num2                ; low byte; carry out -> C
        sta res
        lda num1+1
        adc num2+1              ; high byte + carry from the low byte
        sta res+1
        rts                     ; C=1 here means overflow

; ---------------------------------------------------------------------------
; sub16: res = num1 - num2
; Out: C=0 if the result is negative (num2 > num1)
; Note: on the 6502 the carry is an inverted "borrow": SEC before SBC.
; ---------------------------------------------------------------------------
sub16:
        sec                     ; no borrow into the low byte
        lda num1
        sbc num2
        sta res
        lda num1+1
        sbc num2+1
        sta res+1
        rts                     ; C=0 here means num1 < num2

; ---------------------------------------------------------------------------
; mul16: res (32 bits) = num1 * num2         ("shift and add")
; Out: C=1 if the product does not fit in 16 bits
;
; For each of the 16 bits of num2, from the lowest:
;   if the bit is 1, add num1 to the high half of the product;
;   then shift the whole 32-bit product one place right.
; After 16 rounds the product sits in res..res+3.
; num2 is destroyed.
; ---------------------------------------------------------------------------
mul16:
        lda #0
        sta res+2
        sta res+3               ; A keeps a copy of res+3 through the loop
        ldx #16                 ; 16 bits to examine
@loop:
        lsr num2+1              ; shift num2 right:
        ror num2                ;   its lowest bit falls into C
        bcc @shift              ; bit = 0: nothing to add
        lda res+2               ; bit = 1: high half += num1
        clc
        adc num1
        sta res+2
        lda res+3
        adc num1+1              ; a carry here becomes the 33rd bit...
@shift:
        ror a                   ; ...and is rotated back in from the left
        sta res+3
        ror res+2
        ror res+1
        ror res
        dex
        bne @loop

        lda res+2               ; any bit in the high 16 bits?
        ora res+3
        beq @fits
        sec                     ; yes: overflow
        rts
@fits:
        clc
        rts

; ---------------------------------------------------------------------------
; div16: res = num1 / num2, rem = num1 mod num2      ("shift and subtract")
; Out: C=1 if num2 = 0 (division by zero)
;
; Bits of num1 are moved, one at a time from the top, into rem.
; Whenever rem >= num2, subtract num2 and put a 1 in the quotient
; (which is built in num1 as its bits move out).
; ---------------------------------------------------------------------------
div16:
        lda num2
        ora num2+1
        bne @ok
        sec                     ; division by zero
        rts
@ok:
        lda #0
        sta rem
        sta rem+1
        ldx #16                 ; 16 quotient bits
@loop:
        asl num1                ; next top bit of num1 -> C,
        rol num1+1              ;   a 0 enters at the bottom (quotient bit)
        rol rem                 ; C -> into the remainder
        rol rem+1
        lda rem                 ; try rem - num2
        sec
        sbc num2
        tay                     ; keep the low byte of the difference
        lda rem+1
        sbc num2+1
        bcc @next               ; negative: num2 does not fit, bit stays 0
        sta rem+1               ; it fits: keep the difference...
        sty rem
        inc num1                ; ...and set the quotient bit to 1
@next:
        dex
        bne @loop

        lda num1                ; quotient -> res
        sta res
        lda num1+1
        sta res+1
        clc
        rts
