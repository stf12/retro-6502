; ---------------------------------------------------------------------------
; lib/gfx.inc - graphics library: the interface, the same on every machine
;
;       .include "gfx.inc"      (assemble with -I lib)
;
; Calling convention
;   Parameters go in the gfx_* variables below, 16 bit, low byte first,
;   then the program calls the routine:
;
;       lda #<10
;       sta gfx_x0
;       lda #>10
;       sta gfx_x0+1
;       ...                     ; gfx_y0, gfx_x1, gfx_y1
;       jsr draw_line
;
;   or, for constant values, uses a macro: LINE 10, 20, 300, 150
;
;   Each machine decides where the gfx_* variables live: on the Chiplab
;   they are the GFX chip's parameter registers (no copying at all), on
;   another machine they can be zero-page variables. The program's source
;   is the same.
;
;   The routines change A only; X and Y are kept. They never change the
;   gfx_* variables, so values can be reused: to draw concentric circles,
;   only gfx_r has to change between two calls.
;
; Coordinates: 0..319 across, 0..199 down, (0,0) top left. They are signed
; 16-bit values: shapes may go off screen and are cut at the clip
; rectangle. Sizes (gfx_w, gfx_h, gfx_r) are unsigned.
; ---------------------------------------------------------------------------

; --- routines ----------------------------------------------------------------
        .global gfx_init        ; reset pen, paper, mode and clip; C=0 if the
                                ; graphics are there, C=1 if not
        .global clear_screen    ; fill the clip rectangle with the paper colour
        .global draw_line       ; gfx_x0, gfx_y0 -> gfx_x1, gfx_y1
        .global draw_rect       ; gfx_x, gfx_y, gfx_w, gfx_h: outline
        .global fill_rect       ; gfx_x, gfx_y, gfx_w, gfx_h: filled
        .global draw_circle     ; gfx_cx, gfx_cy, gfx_r: outline
        .global fill_circle     ; gfx_cx, gfx_cy, gfx_r: filled
        .global set_pen         ; A = drawing colour
        .global set_paper       ; A = background colour (for clear_screen)
        .global set_mode        ; A = MODE_COPY or MODE_XOR
        .global set_clip        ; gfx_x, gfx_y, gfx_w, gfx_h: drawing area
        .global reset_clip      ; drawing area = whole screen

; --- parameters (16 bit each) --------------------------------------------------
; Several names share the same place: each routine uses the names that
; suit it.
        .global gfx_x0, gfx_y0, gfx_x1, gfx_y1          ; draw_line
        .global gfx_x, gfx_y, gfx_w, gfx_h              ; rectangles, clip
        .global gfx_cx, gfx_cy, gfx_r                   ; circles

; --- colours (C64 palette) -----------------------------------------------------
BLACK       = 0
WHITE       = 1
RED         = 2
CYAN        = 3
PURPLE      = 4
GREEN       = 5
BLUE        = 6
YELLOW      = 7
ORANGE      = 8
BROWN       = 9
LIGHT_RED   = 10
DARK_GREY   = 11
GREY        = 12
LIGHT_GREEN = 13
LIGHT_BLUE  = 14
LIGHT_GREY  = 15

; --- modes ---------------------------------------------------------------------
MODE_COPY   = 0                 ; the pen colour replaces the pixel
MODE_XOR    = 1                 ; pixel XOR pen: drawing twice restores it

; --- macros for constant values ------------------------------------------------
; Each one stores its arguments in the gfx_* variables, then calls the
; routine. The arguments must be known when assembling (numbers, symbols,
; expressions): for computed values, store the variables yourself.

.macro SET16 var, value         ; var = value, 16 bit, low byte first
        lda #<(value)
        sta var
        lda #>(value)
        sta var+1
.endmacro

.macro LINE x0, y0, x1, y1
        SET16 gfx_x0, x0
        SET16 gfx_y0, y0
        SET16 gfx_x1, x1
        SET16 gfx_y1, y1
        jsr draw_line
.endmacro

.macro RECT left, top, width, height
        SET16 gfx_x, left
        SET16 gfx_y, top
        SET16 gfx_w, width
        SET16 gfx_h, height
        jsr draw_rect
.endmacro

.macro FILL_RECT left, top, width, height
        SET16 gfx_x, left
        SET16 gfx_y, top
        SET16 gfx_w, width
        SET16 gfx_h, height
        jsr fill_rect
.endmacro

.macro CIRCLE cx, cy, r
        SET16 gfx_cx, cx
        SET16 gfx_cy, cy
        SET16 gfx_r, r
        jsr draw_circle
.endmacro

.macro FILL_CIRCLE cx, cy, r
        SET16 gfx_cx, cx
        SET16 gfx_cy, cy
        SET16 gfx_r, r
        jsr fill_circle
.endmacro

.macro CLIP left, top, width, height
        SET16 gfx_x, left
        SET16 gfx_y, top
        SET16 gfx_w, width
        SET16 gfx_h, height
        jsr set_clip
.endmacro

.macro PEN colour
        lda #colour
        jsr set_pen
.endmacro

.macro PAPER colour
        lda #colour
        jsr set_paper
.endmacro
