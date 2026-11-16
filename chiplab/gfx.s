; ---------------------------------------------------------------------------
; chiplab/gfx.s - graphics library for the Chiplab (interface: lib/gfx.inc)
;
; The drawing is done by the GFX chip that tools/chiplab_run.py emulates on
; the Mac (docs/gfx-chip.md). The gfx_* parameters ARE the chip's parameter
; registers P0-P3, so a program writes them directly and each drawing
; routine only has to write the command register.
; ---------------------------------------------------------------------------

        .setcpu "65C02"
        .include "gfx.inc"

; GFX chip registers (docs/gfx-chip.md)
GFX_P0      = $F010
GFX_P1      = $F012
GFX_P2      = $F014
GFX_P3      = $F016
GFX_CMD     = $F020
GFX_VERSION = $F022
GFX_PEN     = $F028
GFX_PAPER   = $F029
GFX_MODE    = $F02A
GFX_CLIP_X0 = $F02C
GFX_CLIP_Y0 = $F02E
GFX_CLIP_X1 = $F030
GFX_CLIP_Y1 = $F032

CMD_CLEAR       = $01
CMD_LINE        = $02
CMD_RECT        = $03
CMD_FILL_RECT   = $04
CMD_CIRCLE      = $05
CMD_FILL_CIRCLE = $06

SCREEN_W = 320
SCREEN_H = 200

; The parameters: names for P0-P3 (declared .global in gfx.inc).
gfx_x0 = GFX_P0
gfx_y0 = GFX_P1
gfx_x1 = GFX_P2
gfx_y1 = GFX_P3
gfx_x  = GFX_P0
gfx_y  = GFX_P1
gfx_w  = GFX_P2
gfx_h  = GFX_P3
gfx_cx = GFX_P0
gfx_cy = GFX_P1
gfx_r  = GFX_P2

        .segment "CODE"

; --- drawing: one write to the command register each -------------------------

clear_screen:
        lda #CMD_CLEAR
        bra command

draw_line:
        lda #CMD_LINE
        bra command

draw_rect:
        lda #CMD_RECT
        bra command

fill_rect:
        lda #CMD_FILL_RECT
        bra command

draw_circle:
        lda #CMD_CIRCLE
        bra command

fill_circle:
        lda #CMD_FILL_CIRCLE
command:
        sta GFX_CMD             ; the chip draws during this write cycle
        rts

; --- pen settings ----------------------------------------------------------------

set_pen:
        sta GFX_PEN
        rts

set_paper:
        sta GFX_PAPER
        rts

set_mode:
        sta GFX_MODE
        rts

; set_clip: the chip wants the clip as corners (x0, y0)-(x1, y1), both
; included; the library takes a rectangle like the other routines:
;   x0 = gfx_x, y0 = gfx_y, x1 = gfx_x + gfx_w - 1, y1 = gfx_y + gfx_h - 1
set_clip:
        lda gfx_x
        sta GFX_CLIP_X0
        lda gfx_x+1
        sta GFX_CLIP_X0+1
        lda gfx_y
        sta GFX_CLIP_Y0
        lda gfx_y+1
        sta GFX_CLIP_Y0+1
        clc                     ; x1 = x + w ...
        lda gfx_x
        adc gfx_w
        sta GFX_CLIP_X1
        lda gfx_x+1
        adc gfx_w+1
        sta GFX_CLIP_X1+1
        lda GFX_CLIP_X1
        bne :+
        dec GFX_CLIP_X1+1       ; ... - 1 (16 bit: borrow from the high
:       dec GFX_CLIP_X1         ; byte when the low byte is 0)
        clc                     ; y1 = y + h - 1, the same way
        lda gfx_y
        adc gfx_h
        sta GFX_CLIP_Y1
        lda gfx_y+1
        adc gfx_h+1
        sta GFX_CLIP_Y1+1
        lda GFX_CLIP_Y1
        bne :+
        dec GFX_CLIP_Y1+1
:       dec GFX_CLIP_Y1
        rts

reset_clip:
        stz GFX_CLIP_X0
        stz GFX_CLIP_X0+1
        stz GFX_CLIP_Y0
        stz GFX_CLIP_Y0+1
        lda #<(SCREEN_W - 1)
        sta GFX_CLIP_X1
        lda #>(SCREEN_W - 1)
        sta GFX_CLIP_X1+1
        lda #<(SCREEN_H - 1)
        sta GFX_CLIP_Y1
        stz GFX_CLIP_Y1+1
        rts

; gfx_init: back to the chip's start-up settings (white pen, black paper,
; COPY mode, whole screen). C=1 if no chip answers (VERSION reads 0).
gfx_init:
        lda #WHITE
        sta GFX_PEN
        lda #BLACK
        sta GFX_PAPER
        stz GFX_MODE
        jsr reset_clip
        lda GFX_VERSION         ; 0: nothing answers at these addresses
        beq none
        clc
        rts
none:   sec
        rts
