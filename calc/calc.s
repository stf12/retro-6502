; ---------------------------------------------------------------------------
; calc.s - a 16-bit unsigned calculator for the 6502
;
; Type an expression and press RETURN:
;     1234*56      300+45      1000/7      90-12
; Spaces are allowed. An empty line ends the program.
;
; The same source runs on the Chiplab (with io_chiplab.s) and on the C64
; (with io_c64.s). On the C64 this file must be linked FIRST: its first
; byte is where BASIC's "SYS 2061" jumps.
; ---------------------------------------------------------------------------

        .include "calc.inc"

        .import num1, num2, res, rem              ; math16.s
        .import add16, sub16, mul16, div16
        .import val, ch                           ; numio.s
        .import read_u16, print_u16, skip_spaces, print_str

        .export main, err_syntax, err_too_big

        .segment "BSS"
entry_sp: .res 1                ; stack pointer when the program started
op:       .res 1                ; the operator character: + - * /

        .segment "CODE"

main:
        tsx                     ; remember the stack level: after an error
        stx entry_sp            ;   we jump back here from anywhere
        lda #<banner
        ldx #>banner
        jsr print_str

; --- read one line: number, operator, number, RETURN ------------------------
next_line:
        lda #<prompt
        ldx #>prompt
        jsr print_str
        jsr io_getc             ; first character of the line
        sta ch
        jsr skip_spaces
        lda ch
        cmp #CR                 ; empty line: quit
        bne @parse
        jmp quit
@parse:
        jsr read_u16            ; first number
        lda val
        sta num1
        lda val+1
        sta num1+1

        jsr skip_spaces
        lda ch                  ; operator
        sta op
        cmp #'+'
        beq @op_ok
        cmp #'-'
        beq @op_ok
        cmp #'*'
        beq @op_ok
        cmp #'/'
        beq @op_ok
        jmp err_syntax
@op_ok:
        jsr io_getc             ; move past the operator
        sta ch

        jsr read_u16            ; second number
        lda val
        sta num2
        lda val+1
        sta num2+1

        jsr skip_spaces
        lda ch
        cmp #CR                 ; nothing else may follow
        beq calculate
        jmp err_syntax

; --- do the operation -------------------------------------------------------
calculate:
        lda op
        cmp #'+'
        beq do_add
        cmp #'-'
        beq do_sub
        cmp #'*'
        beq do_mul
                                ; otherwise it is '/'
do_div:
        jsr div16
        bcc :+
        lda #<msg_div0
        ldx #>msg_div0
        jmp error
:       jsr show_result
        lda #<msg_rem           ; " resto "
        ldx #>msg_rem
        jsr print_str
        lda rem
        sta val
        lda rem+1
        sta val+1
        jsr print_u16
        jsr io_newline
        jmp next_line

do_add:
        jsr add16
        bcs result_too_big
        jmp print_line
do_sub:
        jsr sub16
        bcs print_line          ; C=1: no borrow, result >= 0
        lda #<msg_neg
        ldx #>msg_neg
        jmp error
do_mul:
        jsr mul16
        bcs result_too_big
print_line:
        jsr show_result
        jsr io_newline
        jmp next_line

result_too_big:
        lda #<msg_res_big
        ldx #>msg_res_big
        jmp error

; print "= " and the result
show_result:
        lda #<msg_eq
        ldx #>msg_eq
        jsr print_str
        lda res
        sta val
        lda res+1
        sta val+1
        jmp print_u16

; --- errors -----------------------------------------------------------------
; Called from anywhere, even from inside a subroutine: the stack is reset to
; its level at the start, as if the subroutine calls had never happened.
err_syntax:
        lda #<msg_syntax
        ldx #>msg_syntax
        jmp error
err_too_big:
        lda #<msg_num_big
        ldx #>msg_num_big
error:                          ; A/X = message
        sta ptr                 ; park the message address (not on the
        stx ptr+1               ;   stack: we are about to reset it)
        ldx entry_sp            ; forget all pending subroutine calls
        txs
        lda ptr
        ldx ptr+1
        jsr print_str
        jsr io_newline
@flush:                         ; throw away the rest of the line
        lda ch
        cmp #CR
        beq @done
        jsr io_getc
        sta ch
        jmp @flush
@done:
        jmp next_line

quit:
        ldx entry_sp            ; back to the stack level we started with
        txs
        jmp io_quit             ; C64: RTS to BASIC. Chiplab: stop.

; --- texts ------------------------------------------------------------------
; Written in lowercase: on the C64 the assembler turns them into PETSCII,
; which shows as UPPERCASE on the standard screen.
        .segment "RODATA"
banner:      .byte "calcolatrice 16 bit (0-65535)", CR
             .byte "es. 1234*56  riga vuota = fine", CR, 0
prompt:      .byte "> ", 0
msg_eq:      .byte "= ", 0
msg_rem:     .byte " resto ", 0
msg_syntax:  .byte "errore di sintassi", 0
msg_num_big: .byte "numero troppo grande", 0
msg_res_big: .byte "risultato troppo grande", 0
msg_neg:     .byte "risultato negativo", 0
msg_div0:    .byte "divisione per zero", 0
