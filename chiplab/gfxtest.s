; ---------------------------------------------------------------------------
; gfxtest.s - test picture for the graphics library (lib/gfx.inc)
;
; Exercises every routine: clear_screen, draw_line, draw_rect, fill_rect,
; draw_circle, fill_circle, set_pen, set_paper, set_mode (XOR), set_clip,
; reset_clip. Constant shapes use the macros; the loops store computed
; values in the gfx_* variables themselves.
;
;   make run PROG=gfxtest CYCLES=0
; ---------------------------------------------------------------------------

        .setcpu "65C02"
        .include "gfx.inc"

CONSOLE = $F001
EXIT    = $F000

        .zeropage
x_pos:  .res 2                  ; 16-bit loop variable
text:   .res 2                  ; pointer to the message to print

        .segment "CODE"         ; starts at $8000 (see chiplab.cfg)

reset:
        ldx #$FF
        txs
        jsr gfx_init
        bcc :+
        SET16 text, msg_no_gfx
        jmp report
:

; --- C64 look: dark blue screen, light blue frame ---------------------------
        PAPER BLUE
        jsr clear_screen
        PEN LIGHT_BLUE
        RECT 0, 0, 320, 200

; --- the 16 colours, each with a white frame -----------------------------------
        SET16 gfx_y, 12         ; y, w, h stay the same for the whole loop:
        SET16 gfx_w, 16         ; the routines do not change them
        SET16 gfx_h, 16
        SET16 x_pos, 16
        ldx #0
palette:
        txa                     ; colour = loop counter
        jsr set_pen
        lda x_pos               ; gfx_x = x_pos: a computed value, so no
        sta gfx_x               ; macro here
        lda x_pos+1
        sta gfx_x+1
        jsr fill_rect
        PEN WHITE               ; same rectangle, outlined: blue shows
        jsr draw_rect           ; on the blue screen
        clc                     ; x_pos += 18 (16 bit: it passes 255)
        lda x_pos
        adc #18
        sta x_pos
        lda x_pos+1
        adc #0
        sta x_pos+1
        inx                     ; the routines keep X
        cpx #16
        bne palette

; --- a fan of lines -----------------------------------------------------------
        PEN YELLOW
        SET16 gfx_x0, 60        ; all lines start at (60, 185)
        SET16 gfx_y0, 185
        SET16 gfx_y1, 50        ; and end on y = 50
        SET16 x_pos, 10
fan:
        lda x_pos
        sta gfx_x1
        lda x_pos+1
        sta gfx_x1+1
        jsr draw_line
        clc
        lda x_pos
        adc #20
        sta x_pos
        bcc :+
        inc x_pos+1
:       lda x_pos               ; up to x = 110
        cmp #111
        bcc fan

; --- concentric circles: only the radius changes ------------------------------
        PEN CYAN
        SET16 gfx_cx, 175
        SET16 gfx_cy, 110
        stz gfx_r+1             ; radius < 256: high byte 0
        lda #10
radius:
        sta gfx_r
        pha
        jsr draw_circle
        pla
        clc
        adc #10
        cmp #51
        bcc radius

; --- a filled circle, partly covered by an XOR rectangle ------------------------
        PEN LIGHT_GREEN
        FILL_CIRCLE 265, 110, 35

        lda #MODE_XOR
        jsr set_mode
        PEN WHITE
        FILL_RECT 240, 120, 60, 50      ; inverts what it covers
        RECT 110, 150, 40, 30           ; drawn twice in XOR: it disappears,
        jsr draw_rect                   ; nothing must be left here
        lda #MODE_COPY
        jsr set_mode

; --- clipping: a disc cut by the clip rectangle -------------------------------
        CLIP 200, 172, 101, 19          ; x 200-300, y 172-190
        PEN ORANGE
        FILL_CIRCLE 250, 195, 40        ; goes below the screen too
        jsr reset_clip

        SET16 text, msg_done
report:
        ldy #0
print:
        lda (text),y
        beq done
        sta CONSOLE
        iny
        bra print
done:
        sta EXIT

nmi_irq:
        rti

msg_done:
        .byte "gfx library test done", $0D, $0A, 0
msg_no_gfx:
        .byte "no graphics chip found", $0D, $0A, 0

        .segment "VECTORS"      ; $FFFA-$FFFF
        .word nmi_irq           ; NMI
        .word reset             ; RESET
        .word nmi_irq           ; IRQ/BRK
