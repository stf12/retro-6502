; ---------------------------------------------------------------------------
; window.s - a window in the style of the Macintosh Classic, drawn with the
; graphics library (lib/gfx.inc)
;
; Grey desktop, menu bar, a window with a shadow, a striped title bar and a
; close box. The content, rainbow rings and a 6502 chip, is drawn with the
; clip rectangle set to the window's inside, so it cannot spill over the
; frame: the way QuickDraw kept each window's drawing in its own window.
;
;   make run PROG=window CYCLES=0
; ---------------------------------------------------------------------------

        .setcpu "65C02"
        .include "gfx.inc"

CONSOLE = $F001
EXIT    = $F000

; The window
WIN_X   = 40
WIN_Y   = 30
WIN_W   = 240
WIN_H   = 150
TITLE_H = 18                    ; title bar height, frame line included

; The chip: a 40-pin DIP package, 20 pins on each long side
CHIP_X  = 90
CHIP_Y  = 92
CHIP_W  = 140
CHIP_H  = 46
PIN_W   = 3
PIN_H   = 6
PIN_GAP = 7                     ; from one pin to the next

; The "6502" on the chip: digits made of rectangles, like a 7-segment
; display. Each digit is 12 x 20 pixels, strokes 3 pixels thick.
DIGIT_W = 12
DIGIT_STEP = 18                 ; digit width + space
TEXT_X  = CHIP_X + (CHIP_W - 3*DIGIT_STEP - DIGIT_W) / 2
TEXT_Y  = CHIP_Y + 13

        .segment "CODE"         ; starts at $8000 (see chiplab.cfg)

reset:
        ldx #$FF
        txs
        jsr gfx_init

; --- desktop and menu bar ----------------------------------------------------
        PAPER GREY
        jsr clear_screen

        PEN WHITE
        FILL_RECT 0, 0, 320, 12
        PEN BLACK
        LINE 0, 12, 319, 12
        PEN DARK_GREY           ; menu titles: blocks where the words go
        FILL_RECT 12, 4, 8, 5
        FILL_RECT 30, 4, 20, 5
        FILL_RECT 60, 4, 20, 5
        FILL_RECT 90, 4, 28, 5

; --- the window: shadow, white body, black frame ---------------------------------
        PEN BLACK
        FILL_RECT WIN_X+2, WIN_Y+2, WIN_W, WIN_H
        PEN WHITE
        FILL_RECT WIN_X, WIN_Y, WIN_W, WIN_H
        PEN BLACK
        RECT WIN_X, WIN_Y, WIN_W, WIN_H

; --- title bar: horizontal stripes, every other line ----------------------------
        SET16 gfx_x0, WIN_X+2
        SET16 gfx_x1, WIN_X+WIN_W-3
        stz gfx_y0+1            ; y < 256: high bytes 0
        stz gfx_y1+1
        lda #WIN_Y+3
stripe:
        sta gfx_y0              ; a horizontal line: y0 = y1
        sta gfx_y1
        pha                     ; the routines change A
        jsr draw_line
        pla
        clc
        adc #2
        cmp #WIN_Y+TITLE_H-3
        bcc stripe

        PEN WHITE               ; gap for the title, gap for the close box
        FILL_RECT WIN_X+WIN_W/2-40, WIN_Y+2, 80, TITLE_H-4
        FILL_RECT WIN_X+7, WIN_Y+3, 13, 11
        PEN BLACK
        RECT WIN_X+8, WIN_Y+4, 11, 9            ; the close box
        PEN DARK_GREY
        FILL_RECT WIN_X+WIN_W/2-24, WIN_Y+7, 48, 5  ; where the title goes
        PEN BLACK
        LINE WIN_X, WIN_Y+TITLE_H, WIN_X+WIN_W-1, WIN_Y+TITLE_H

; --- content: rings, cut at the window's inside ---------------------------------
        CLIP WIN_X+1, WIN_Y+TITLE_H+1, WIN_W-2, WIN_H-TITLE_H-2
        SET16 gfx_cx, 250       ; centre near the bottom right corner:
        SET16 gfx_cy, 190       ; most of each disc falls outside
        stz gfx_r+1
        ldx #0                  ; X: ring number, picks the colour
        lda #180                ; A: radius, from the largest disc down
ring:
        sta gfx_r
        pha
        lda colours,x
        jsr set_pen
        jsr fill_circle         ; each smaller disc covers the middle
        pla                     ; of the previous one: rings remain
        inx
        cpx #COLOURS
        bne :+
        ldx #0
:       sec
        sbc #12
        cmp #12
        bcs ring

; --- the 6502 chip, on top of the rings -----------------------------------------
        PEN BLACK
        FILL_RECT CHIP_X, CHIP_Y, CHIP_W, CHIP_H

        PEN LIGHT_GREY          ; 20 pins on top, 20 below
        SET16 gfx_w, PIN_W
        SET16 gfx_h, PIN_H
        stz gfx_x+1             ; all coordinates < 256: high bytes 0
        stz gfx_y+1
        ldx #CHIP_X+2           ; X: x of the pin (the routines keep X)
pin:
        stx gfx_x
        lda #CHIP_Y-PIN_H       ; the pin above the body ...
        sta gfx_y
        jsr fill_rect
        lda #CHIP_Y+CHIP_H      ; ... and the one below, same x
        sta gfx_y
        jsr fill_rect
        txa
        clc
        adc #PIN_GAP
        tax
        cpx #CHIP_X+2+20*PIN_GAP
        bne pin

        CLIP CHIP_X, CHIP_Y, CHIP_W, CHIP_H     ; the notch: a disc cut
        PEN DARK_GREY                           ; at the body's left edge,
        FILL_CIRCLE CHIP_X, CHIP_Y+CHIP_H/2, 6  ; so only half of it shows
        FILL_CIRCLE CHIP_X+8, CHIP_Y+CHIP_H-8, 2  ; pin 1 dot

        PEN LIGHT_GREY          ; the text, one rectangle per segment
        stz gfx_w+1
        stz gfx_h+1
        ldx #0
segment:
        lda segments,x          ; x, y, width, height; $FF ends the table
        cmp #$FF
        beq text_done
        sta gfx_x
        lda segments+1,x
        sta gfx_y
        lda segments+2,x
        sta gfx_w
        lda segments+3,x
        sta gfx_h
        jsr fill_rect
        inx
        inx
        inx
        inx
        bra segment
text_done:
        jsr reset_clip

        ldy #0
print:
        lda message,y
        beq done
        sta CONSOLE
        iny
        bra print
done:
        sta EXIT

nmi_irq:
        rti

colours:
        .byte RED, ORANGE, YELLOW, LIGHT_GREEN, GREEN, CYAN
        .byte LIGHT_BLUE, BLUE, PURPLE, LIGHT_RED
COLOURS = * - colours

; Segments of digit n (0-3), in pixels from the digit's top left corner
.macro SEG n, sx, sy, sw, sh
        .byte TEXT_X + (n)*DIGIT_STEP + (sx), TEXT_Y + (sy), sw, sh
.endmacro
TOP     = 0                     ; y of the three horizontal strokes
MIDDLE  = 8
BOTTOM  = 17

segments:
        SEG 0, 0, TOP, 12, 3    ; 6
        SEG 0, 0, MIDDLE, 12, 3
        SEG 0, 0, BOTTOM, 12, 3
        SEG 0, 0, 0, 3, 20      ;   left side, full height
        SEG 0, 9, MIDDLE, 3, 12 ;   lower right
        SEG 1, 0, TOP, 12, 3    ; 5
        SEG 1, 0, MIDDLE, 12, 3
        SEG 1, 0, BOTTOM, 12, 3
        SEG 1, 0, 0, 3, 11      ;   upper left
        SEG 1, 9, MIDDLE, 3, 12 ;   lower right
        SEG 2, 0, TOP, 12, 3    ; 0
        SEG 2, 0, BOTTOM, 12, 3
        SEG 2, 0, 0, 3, 20      ;   left side
        SEG 2, 9, 0, 3, 20      ;   right side
        SEG 3, 0, TOP, 12, 3    ; 2
        SEG 3, 0, MIDDLE, 12, 3
        SEG 3, 0, BOTTOM, 12, 3
        SEG 3, 9, 0, 3, 11      ;   upper right
        SEG 3, 0, MIDDLE, 3, 12 ;   lower left
        .byte $FF

message:
        .byte "window demo done", $0D, $0A, 0

        .segment "VECTORS"      ; $FFFA-$FFFF
        .word nmi_irq           ; NMI
        .word reset             ; RESET
        .word nmi_irq           ; IRQ/BRK
