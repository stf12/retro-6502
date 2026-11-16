; ---------------------------------------------------------------------------
; gfxtest.s - test picture for the GFX chip (docs/gfx-chip.md, v1)
;
; Uses the chip's registers directly, to check every command and setting:
; CLEAR, LINE, RECT, FILL_RECT, CIRCLE, FILL_CIRCLE, PEN, PAPER, MODE (XOR),
; the clip rectangle, STATUS and VERSION. Programs will normally call the
; gfx.s library instead.
;
;   make run PROG=gfxtest CYCLES=0
; ---------------------------------------------------------------------------

        .setcpu "65C02"

CONSOLE = $F001
EXIT    = $F000

; GFX chip registers
GFX_P0      = $F010             ; P0-P7: 16 bit each, low byte first
GFX_P2      = $F014
GFX_CMD     = $F020
GFX_STATUS  = $F021
GFX_VERSION = $F022
GFX_PEN     = $F028
GFX_PAPER   = $F029
GFX_MODE    = $F02A
GFX_CLIP_X0 = $F02C
GFX_CLIP_Y0 = $F02E
GFX_CLIP_X1 = $F030
GFX_CLIP_Y1 = $F032

; Commands
CMD_CLEAR       = $01
CMD_LINE        = $02
CMD_RECT        = $03
CMD_FILL_RECT   = $04
CMD_CIRCLE      = $05
CMD_FILL_CIRCLE = $06

; Colours (C64 palette)
BLACK = 0
WHITE = 1
CYAN = 3
BLUE = 6
YELLOW = 7
ORANGE = 8
LIGHT_GREEN = 13
LIGHT_BLUE = 14

; Store a 16-bit constant in a register pair, low byte first.
.macro set16 reg, value
        lda #<(value)
        sta reg
        lda #>(value)
        sta reg+1
.endmacro

; Parameter n (0-7) = value
.macro param n, value
        set16 GFX_P0+2*(n), value
.endmacro

.macro gfx command
        lda #command
        sta GFX_CMD             ; drawn before the next instruction
.endmacro

        .zeropage
x_pos:  .res 2                  ; 16-bit loop variable
text:   .res 2                  ; pointer to the message to print

        .segment "CODE"         ; starts at $8000 (see chiplab.cfg)

reset:
        ldx #$FF
        txs

; --- C64 look: dark blue screen, light blue frame ---------------------------
        lda #BLUE
        sta GFX_PAPER
        gfx CMD_CLEAR

        lda #LIGHT_BLUE
        sta GFX_PEN
        param 0, 0
        param 1, 0
        param 2, 320
        param 3, 200
        gfx CMD_RECT

; --- the 16 colours: FILL_RECT and RECT in a loop -----------------------------
        set16 x_pos, 16
        param 1, 12             ; y, w, h stay the same for the whole loop
        param 2, 16
        param 3, 16
        ldx #0
palette:
        stx GFX_PEN             ; colour = loop counter
        lda x_pos
        sta GFX_P0
        lda x_pos+1
        sta GFX_P0+1
        gfx CMD_FILL_RECT
        lda #WHITE              ; same P0-P3: a white frame around it,
        sta GFX_PEN             ; so blue shows on the blue screen
        gfx CMD_RECT
        clc                     ; x_pos += 18 (16 bit: it passes 255)
        lda x_pos
        adc #18
        sta x_pos
        lda x_pos+1
        adc #0
        sta x_pos+1
        inx
        cpx #16
        bne palette

; --- a fan of lines -----------------------------------------------------------
        lda #YELLOW
        sta GFX_PEN
        param 0, 60             ; all lines start at (60, 185)
        param 1, 185
        param 3, 50             ; and end on y = 50
        set16 x_pos, 10
fan:
        lda x_pos
        sta GFX_P2
        lda x_pos+1
        sta GFX_P2+1
        gfx CMD_LINE
        clc
        lda x_pos
        adc #20
        sta x_pos
        bcc :+
        inc x_pos+1
:       lda x_pos               ; up to x = 110
        cmp #111
        bcc fan

; --- concentric circles: only the radius (P2) changes -------------------------
        lda #CYAN
        sta GFX_PEN
        param 0, 175
        param 1, 110
        lda #10
radius:
        sta GFX_P2              ; P2 high byte is still 0
        pha
        gfx CMD_CIRCLE
        pla
        clc
        adc #10
        cmp #51
        bcc radius

; --- a filled circle, partly covered by an XOR square ----------------------------
        lda #LIGHT_GREEN
        sta GFX_PEN
        param 0, 265
        param 1, 110
        param 2, 35
        gfx CMD_FILL_CIRCLE

        lda #1                  ; MODE = XOR
        sta GFX_MODE
        lda #WHITE
        sta GFX_PEN
        param 0, 240
        param 1, 120
        param 2, 60
        param 3, 50
        gfx CMD_FILL_RECT       ; inverts what it covers

        param 0, 110            ; a rectangle drawn twice in XOR
        param 1, 150            ; disappears: nothing must be left here
        param 2, 40
        param 3, 30
        gfx CMD_RECT
        gfx CMD_RECT
        stz GFX_MODE            ; back to COPY

; --- clipping: a disc cut by the clip rectangle -------------------------------
        set16 GFX_CLIP_X0, 200
        set16 GFX_CLIP_Y0, 172
        set16 GFX_CLIP_X1, 300
        set16 GFX_CLIP_Y1, 190
        lda #ORANGE
        sta GFX_PEN
        param 0, 250
        param 1, 195            ; the circle goes below the screen too
        param 2, 40
        gfx CMD_FILL_CIRCLE
        set16 GFX_CLIP_X0, 0    ; whole screen again
        set16 GFX_CLIP_Y0, 0
        set16 GFX_CLIP_X1, 319
        set16 GFX_CLIP_Y1, 199

; --- VERSION and STATUS -------------------------------------------------------
        set16 text, msg_fail
        lda GFX_VERSION
        cmp #1
        bne report
        lda #$7F                ; an unknown command ...
        sta GFX_CMD
        lda GFX_STATUS          ; ... must set bit 0
        and #1
        beq report
        gfx 0                   ; NOP clears STATUS
        lda GFX_STATUS
        bne report
        set16 text, msg_ok
report:
        ldy #0
print:
        lda (text),y            ; the message pointed to by text
        beq done
        sta CONSOLE
        iny
        bra print
done:
        sta EXIT

nmi_irq:
        rti

msg_ok:
        .byte "gfx chip v1: version and status OK", $0D, $0A, 0
msg_fail:
        .byte "gfx chip: version or status WRONG", $0D, $0A, 0

        .segment "VECTORS"      ; $FFFA-$FFFF
        .word nmi_irq           ; NMI
        .word reset             ; RESET
        .word nmi_irq           ; IRQ/BRK
