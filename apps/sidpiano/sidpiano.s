; ---------------------------------------------------------------------------
; sidpiano.s - a live SID piano for the Commodore 64 (PAL)
;
; The C64 keyboard is read straight from the CIA1 key matrix, so several keys
; can be down at once (chords) and a key release is seen immediately. This is
; impossible through the KERNAL (GETIN), which only reports key presses.
;
; Keys
;   lower row   z s x d c v g b h n j m ,      one octave + 1 note
;               (s d g h j are the black keys)
;   upper row   q 2 w 3 e r 5 t 6 y 7 u i      the octave above
;   f1 f3 f5 f7       waveform: triangle, sawtooth, pulse, noise
;   + -               octave up / down
;   cursor up/down    select a parameter     (with SHIFT: the other way)
;   cursor left/right change its value       (with SHIFT: the other way)
;   run/stop          back to BASIC
;
; Up to three notes sound at once, one per SID voice. All voices share the
; same patch (waveform, ADSR, pulse width, filter).
;
; Structure
;   - A raster IRQ at line 250 (once per PAL frame, 50 Hz) replaces the KERNAL
;     IRQ: it scans the keyboard, handles the controls and drives the SID.
;   - The main loop only redraws the screen when something has changed.
;
; Build: make sidpiano  ->  build/sidpiano.prg   (then RUN in BASIC)
; ---------------------------------------------------------------------------

        .setcpu "6502"
        .macpack cbm            ; scrcode: ASCII -> screen codes
                                ; (write text in lowercase: the standard
                                ; charset shows it as UPPERCASE)

; --- hardware ---------------------------------------------------------------

SCREEN  = $0400
COLORRAM = $D800

SID     = $D400                 ; voice v at SID + 7*v:
                                ;   +0/+1 frequency, +2/+3 pulse width,
                                ;   +4 control, +5 attack/decay, +6 sustain/release
SID_FCLO = $D415                ; filter cutoff, low 3 bits
SID_FCHI = $D416                ; filter cutoff, high 8 bits
SID_RES  = $D417                ; resonance (high nibble), voice routing
SID_MODE = $D418                ; filter mode (bits 4-6), volume (low nibble)

VIC_CTRL1 = $D011               ; bit 7 = raster line bit 8
VIC_RASTER = $D012
VIC_IRQFLAG = $D019
VIC_IRQMASK = $D01A
VIC_BORDER = $D020
VIC_BACKGROUND = $D021

CIA1_PRA = $DC00                ; keyboard matrix: column select (active low)
CIA1_PRB = $DC01                ; keyboard matrix: rows (0 = key down)
CIA1_DDRA = $DC02
CIA1_DDRB = $DC03
CIA1_ICR  = $DC0D

IRQ_VECTOR = $0314              ; KERNAL IRQ vector (RAM)
IRQ_EXIT   = $EA81              ; KERNAL: pull Y, X, A and RTI
K_CLRSCR   = $E544              ; KERNAL: clear the screen
K_IOINIT   = $FF84
K_RESTOR   = $FF8A
K_CINT     = $FF81

; Free zero page locations for the screen pointers
dst     = $FB
src     = $FD

; --- parameters (the editable patch) ------------------------------------------

P_WAVE  = 0                     ; 0 tri, 1 saw, 2 pulse, 3 noise
P_ATK   = 1
P_DEC   = 2
P_SUS   = 3
P_REL   = 4
P_PW    = 5                     ; pulse width, 8 = 50 %
P_FMODE = 6                     ; 0 off, 1 low pass, 2 band pass, 3 high pass
P_CUT   = 7
P_RES   = 8
P_OCT   = 9                     ; octave of the lower key row, 0-5
NPARAMS = 10

NKEYS   = 26                    ; piano keys: 13 + 13
FIRST_ROW = 4                   ; screen row of the first parameter
VOICE_ROW = 16                  ; screen row of voice 1

; --- code ---------------------------------------------------------------------

        .segment "CODE"

; BASIC's SYS jumps here: this must stay the first code of the program.
start:
        ; silence the SID
        ldx #$18
        lda #0
@sid:   sta SID,x
        dex
        bpl @sid

        ; clear the program state
        ldx #7
        lda #0
@keys:  sta keys,x
        sta prev,x
        dex
        bpl @keys
        sta quit
        sta sel
        sta nextvoice
        sta patchdirty
        lda #1
        sta dirty
        lda #$FF
        sta voicekey
        sta voicekey+1
        sta voicekey+2

        ; load the default patch
        ldx #NPARAMS-1
@def:   lda param_default,x
        sta param_val,x
        dex
        bpl @def

        ; keyboard matrix: port A drives the columns, port B reads the rows
        lda #$FF
        sta CIA1_DDRA
        lda #$00
        sta CIA1_DDRB

        ; screen
        lda #0
        sta VIC_BORDER
        sta VIC_BACKGROUND
        jsr K_CLRSCR
        jsr draw_static
        jsr apply_patch

        ; take over the IRQ: one raster interrupt per frame, no CIA timer
        sei
        lda IRQ_VECTOR
        sta old_irq
        lda IRQ_VECTOR+1
        sta old_irq+1
        lda #<irq
        sta IRQ_VECTOR
        lda #>irq
        sta IRQ_VECTOR+1
        lda #$7F
        sta CIA1_ICR            ; CIA1 interrupts off
        lda CIA1_ICR            ; acknowledge a pending one
        lda VIC_CTRL1
        and #$7F                ; raster line bit 8 = 0
        sta VIC_CTRL1
        lda #250
        sta VIC_RASTER          ; just below the visible screen
        lda #$FF
        sta VIC_IRQFLAG
        lda #$01
        sta VIC_IRQMASK         ; raster interrupt on
        cli

; The IRQ does the work: here we only redraw when something has changed.
main:
        lda quit
        bne leave
        lda dirty
        beq main
        lda #0
        sta dirty
        jsr draw_params
        jsr draw_voices
        jmp main

; Back to BASIC: stop our IRQ, silence the SID, let the KERNAL reset the
; CIAs, its vectors and the screen.
leave:
        sei
        lda #0
        sta VIC_IRQMASK
        lda #$FF
        sta VIC_IRQFLAG
        ldx #$18
        lda #0
@sid:   sta SID,x
        dex
        bpl @sid
        jsr K_IOINIT
        jsr K_RESTOR
        jsr K_CINT
        cli
        rts

; --- interrupt ------------------------------------------------------------------

irq:
        lda #$01
        sta VIC_IRQFLAG         ; acknowledge the raster interrupt
        jsr frame
        jmp IRQ_EXIT            ; skips the KERNAL keyboard scan

; One frame of work. Kept separate from the IRQ entry so it can be called on
; its own (for example by a test harness).
frame:
        jsr scan_keys
        jsr handle_ui
        jsr scan_piano
        jsr update_voices
        ldx #7                  ; remember this frame's keys for edge detection
@prev:  lda keys,x
        sta prev,x
        dex
        bpl @prev
        rts

; --- keyboard -------------------------------------------------------------------

; keys[c] gets one bit per row for column c: 1 = key down.
scan_keys:
        ldx #7
@col:   lda col_select,x
        sta CIA1_PRA
        lda CIA1_PRB            ; dummy read: let the lines settle
        lda CIA1_PRB
        eor #$FF
        sta keys,x
        dex
        bpl @col
        lda #$FF
        sta CIA1_PRA
        rts

; pk[k] is non zero when piano key k is down.
scan_piano:
        ldy #NKEYS-1
@k:     ldx key_col,y
        lda keys,x
        and key_mask,y
        sta pk,y
        dey
        bpl @k
        rts

; Skip to <skip> unless the key (column, row mask) went down this frame.
.macro SKIP_UNLESS_NEW col, mask, skip
        lda keys+col
        and #mask
        beq skip
        lda prev+col
        and #mask
        bne skip
.endmacro

; --- controls -------------------------------------------------------------------

handle_ui:
        ; shiftflag = 1 while either SHIFT key is down
        lda keys+1
        and #$80                ; left shift
        sta tmp
        lda keys+6
        and #$10                ; right shift
        ora tmp
        beq @noshift
        lda #1
@noshift:
        sta shiftflag

        ; f1 f3 f5 f7 select the waveform
        ldx #3
@wk:    ldy wavekey_col,x
        lda keys,y
        and wavekey_mask,x
        beq @wnext
        lda prev,y
        and wavekey_mask,x
        bne @wnext
        stx param_val+P_WAVE
        jsr changed
@wnext: dex
        bpl @wk

        ; + and - change the octave
        SKIP_UNLESS_NEW 5, $01, @noplus
        lda #1
        ldx #P_OCT
        jsr adjust
@noplus:
        SKIP_UNLESS_NEW 5, $08, @nominus
        lda #$FF
        ldx #P_OCT
        jsr adjust
@nominus:

        ; cursor up/down: select a parameter
        SKIP_UNLESS_NEW 0, $80, @nocud
        lda sel
        ldx shiftflag
        bne @up
        clc
        adc #1
        cmp #NPARAMS
        bcc @store
        lda #0
        beq @store
@up:    sec
        sbc #1
        bpl @store
        lda #NPARAMS-1
@store: sta sel
        jsr changed
@nocud:

        ; cursor left/right: change the selected parameter, with auto repeat
        lda keys
        and #$04
        beq @lrdone             ; not down
        lda prev
        and #$04
        beq @lrnew              ; just went down
        dec repeat
        bne @lrdone
        lda #3                  ; repeat rate
        sta repeat
        bne @lrfire
@lrnew: lda #15                 ; delay before the repeat starts
        sta repeat
@lrfire:
        lda #1
        ldx shiftflag
        beq @right
        lda #$FF
@right: ldx sel
        jsr adjust
@lrdone:

        ; run/stop leaves the program
        lda keys+7
        and #$80
        beq @nostop
        lda #1
        sta quit
@nostop:

        lda patchdirty
        beq @nopatch
        lda #0
        sta patchdirty
        jsr apply_patch
@nopatch:
        rts

; Add the signed step in A ($01 or $FF) to parameter X, within 0..max.
adjust:
        clc
        adc param_val,x
        bpl @pos
        lda #0                  ; went below zero
        beq @set
@pos:   cmp param_max,x
        bcc @set
        beq @set
        lda param_max,x
@set:   cmp param_val,x
        beq @same
        sta param_val,x
        jsr changed
@same:  rts

changed:
        lda #1
        sta dirty
        sta patchdirty
        rts

; --- SID ------------------------------------------------------------------------

; Write the patch to the SID: envelope, pulse width and control register of
; every voice, then the filter and the volume.
apply_patch:
        ldx param_val+P_WAVE
        lda wave_ctrl,x
        sta ctrlbits

        lda param_val+P_ATK     ; attack/decay and sustain/release bytes
        asl
        asl
        asl
        asl
        ora param_val+P_DEC
        sta ad_val
        lda param_val+P_SUS
        asl
        asl
        asl
        asl
        ora param_val+P_REL
        sta sr_val

        ldx #2
@voice: ldy voice_off,x
        lda ad_val
        sta SID+5,y
        lda sr_val
        sta SID+6,y
        lda #0
        sta SID+2,y             ; pulse width, low byte
        lda param_val+P_PW
        sta SID+3,y             ; pulse width, high nibble
        lda ctrlbits            ; a sounding voice keeps its gate on
        ldy voicekey,x
        bmi @idle
        ora #$01
@idle:  ldy voice_off,x
        sta SID+4,y
        dex
        bpl @voice

        lda #0
        sta SID_FCLO
        lda param_val+P_CUT
        asl
        asl
        asl
        asl
        sta SID_FCHI
        lda param_val+P_RES
        asl
        asl
        asl
        asl
        ldx param_val+P_FMODE
        beq @nofilter
        ora #$07                ; route the three voices through the filter
@nofilter:
        sta SID_RES
        lda fmode_bits,x
        ora #$0F                ; full volume
        sta SID_MODE
        rts

; Voices and keys: release the voices whose key went up, then give a free
; voice to every newly pressed key.
update_voices:
        ldx #2
@rel:   ldy voicekey,x
        bmi @nextrel            ; voice is free
        lda pk,y
        bne @nextrel            ; key still down
        lda #$FF
        sta voicekey,x
        ldy voice_off,x
        lda ctrlbits            ; gate off: the release phase starts
        sta SID+4,y
        lda #1
        sta dirty
@nextrel:
        dex
        bpl @rel

        ldy #0
@key:   lda pk,y
        beq @nextkey
        tya                     ; already playing on a voice?
        ldx #2
@chk:   cmp voicekey,x
        beq @nextkey
        dex
        bpl @chk
        lda #3                  ; look for a free voice, round robin
        sta tmp
        ldx nextvoice
@find:  lda voicekey,x
        bmi @got
        inx
        cpx #3
        bcc @same
        ldx #0
@same:  dec tmp
        bne @find
        beq @nextkey            ; all three voices busy: ignore the key
@got:   tya
        sta voicekey,x
        jsr note_on
        lda #1
        sta dirty
        inx                     ; the next search starts after this voice
        cpx #3
        bcc @keep
        ldx #0
@keep:  stx nextvoice
@nextkey:
        iny
        cpy #NKEYS
        bne @key
        rts

; Start piano key Y on voice X. Keeps X and Y.
note_on:
        tya
        pha
        txa
        pha
        stx vtmp
        ldx param_val+P_OCT
        lda oct12,x
        clc
        adc key_note,y          ; absolute semitone, C0 = 0
        ldx vtmp
        sta voicenote,x         ; kept for the display
        ldy #0                  ; Y = octave of the note
@div:   cmp #12
        bcc @pc
        sbc #12
        iny
        bne @div
@pc:    asl                     ; A = pitch class * 2
        tax
        lda freq_tab,x          ; frequency in octave 7 ...
        sta fl
        lda freq_tab+1,x
        sta fh
        sty tmp
        lda #7
        sec
        sbc tmp
        tax                     ; ... shifted down 7 - octave times
        beq @write
@shift: lsr fh
        ror fl
        dex
        bne @shift
@write: ldx vtmp
        ldy voice_off,x
        lda fl
        sta SID,y
        lda fh
        sta SID+1,y
        lda ctrlbits
        ora #$01                ; gate on: attack starts
        sta SID+4,y
        pla
        tax
        pla
        tay
        rts

; --- screen -----------------------------------------------------------------------

.macro PUTS row, col, str
        lda #<(SCREEN + row*40 + col)
        sta dst
        lda #>(SCREEN + row*40 + col)
        sta dst+1
        lda #<str
        ldy #>str
        jsr puts
.endmacro

; Copy the zero terminated string at A (low) / Y (high) to dst.
puts:
        sta src
        sty src+1
        ldy #0
@c:     lda (src),y
        beq @done
        sta (dst),y
        iny
        bne @c
@done:  rts

; Everything that never changes.
draw_static:
        ldx #0                  ; colour RAM: light green text
        lda #13
@col:   sta COLORRAM,x
        sta COLORRAM+$100,x
        sta COLORRAM+$200,x
        sta COLORRAM+$300,x
        inx
        bne @col
        lda #1                  ; white title
        ldx #39
@title: sta COLORRAM,x
        dex
        bpl @title

        PUTS 0, 7, s_title
        PUTS 2, 3, s_param
        PUTS 15, 3, s_voices
        PUTS 16, 3, s_v1
        PUTS 17, 3, s_v2
        PUTS 18, 3, s_v3
        PUTS 19, 5, s_black_up
        PUTS 20, 4, s_white_up
        PUTS 21, 5, s_black_low
        PUTS 22, 4, s_white_low
        PUTS 20, 23, s_oct_up
        PUTS 22, 23, s_oct_low
        PUTS 23, 1, s_help1
        PUTS 24, 1, s_help2
        rts

; The parameter list: marker, name and value (text or hex digit and bar).
draw_params:
        lda #0
        sta pidx
@row:   lda pidx
        clc
        adc #FIRST_ROW
        tay
        lda row_lo,y
        sta dst
        lda row_hi,y
        sta dst+1

        ldx pidx                ; selection marker in column 1
        lda #$20
        cpx sel
        bne @nomark
        lda #$3E                ; '>'
@nomark:
        ldy #1
        sta (dst),y

        lda name_off,x          ; name in columns 3-12
        tax
        ldy #3
@name:  lda param_names,x
        sta (dst),y
        inx
        iny
        cpy #13
        bne @name

        ldx pidx
        cpx #P_WAVE
        beq @wave
        cpx #P_FMODE
        beq @fmode

        lda param_val,x         ; hex digit in column 14, bar in 16-30
        tax
        lda hexdig,x
        ldy #14
        sta (dst),y
        stx tmp                 ; value: the bar has this many filled cells
        ldx #0
        ldy #16
@bar:   lda #$2E                ; '.' for an empty cell
        cpx tmp
        bcs @empty
        lda #$A0                ; reverse space for a filled one
@empty: sta (dst),y
        iny
        inx
        cpx #15
        bne @bar
        jmp @next
@wave:  ldy param_val+P_WAVE
        ldx wave_off,y
        ldy #14
@w1:    lda wave_names,x
        sta (dst),y
        inx
        iny
        cpy #19
        bne @w1
        jmp @next
@fmode: ldy param_val+P_FMODE
        ldx fmode_off,y
        ldy #14
@f1:    lda fmode_names,x
        sta (dst),y
        inx
        iny
        cpy #19
        bne @f1
@next:  inc pidx
        lda pidx
        cmp #NPARAMS
        beq @end
        jmp @row                ; too far for a branch
@end:   rts

; The three voices: the note each one is playing, or ---.
draw_voices:
        ldx #2
@v:     stx vtmp
        txa
        clc
        adc #VOICE_ROW
        tay
        lda row_lo,y            ; the note goes in column 8
        clc
        adc #8
        sta dst
        lda row_hi,y
        adc #0
        sta dst+1
        ldy voicekey,x
        bpl @playing
        lda #$2D                ; '-'
        ldy #0
        sta (dst),y
        iny
        sta (dst),y
        iny
        sta (dst),y
        jmp @next
@playing:
        lda voicenote,x
        ldy #0                  ; Y = octave
@div:   cmp #12
        bcc @pc
        sbc #12
        iny
        bne @div
@pc:    asl                     ; A = pitch class * 2
        tax
        sty tmp
        ldy #0
        lda note_names,x
        sta (dst),y
        iny
        lda note_names+1,x
        sta (dst),y
        iny
        lda tmp
        clc
        adc #$30                ; octave digit
        sta (dst),y
@next:  ldx vtmp
        dex
        bpl @v
        rts

; --- data -------------------------------------------------------------------------

        .segment "RODATA"

col_select:
        .byte $FE, $FD, $FB, $F7, $EF, $DF, $BF, $7F

; Piano keys: matrix column, row mask and note (semitones above the C of the
; octave). Lower row z s x d c v g b h n j m ',' then upper row q 2 w 3 e r 5 t 6 y 7 u i.
key_col:
        .byte 1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 5
        .byte 7, 7, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4
key_mask:
        .byte $10, $20, $80, $04, $10, $80, $04, $10, $20, $80, $04, $10, $80
        .byte $40, $08, $02, $01, $40, $02, $01, $40, $08, $02, $01, $40, $02
key_note:
        .byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
        .byte 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24

; f1 f3 f5 f7 (all in column 0)
wavekey_col:
        .byte 0, 0, 0, 0
wavekey_mask:
        .byte $10, $20, $40, $08

; SID control register waveform bits: triangle, sawtooth, pulse, noise
wave_ctrl:
        .byte $10, $20, $40, $80
; SID mode register filter bits: off, low pass, band pass, high pass
fmode_bits:
        .byte $00, $10, $20, $40

param_max:
        .byte 3, 15, 15, 15, 15, 15, 3, 15, 15, 5
param_default:
        .byte 2, 0, 9, 4, 6, 8, 0, 8, 4, 3

voice_off:
        .byte 0, 7, 14
oct12:
        .byte 0, 12, 24, 36, 48, 60

; PAL SID frequency register values for C7 ... A#7 (B7 does not fit in 16 bits
; and is never used: the highest note is C7). Lower octaves shift this right.
; register = Hz * 2^24 / 985248
freq_tab:
        .word 35641, 37760, 40005, 42384, 44904, 47574
        .word 50403, 53401, 56576, 59940, 63504, 65535

hexdig:
        .byte $30, $31, $32, $33, $34, $35, $36, $37, $38, $39
        .byte $01, $02, $03, $04, $05, $06

row_lo:
        .repeat 25, r
        .byte <(SCREEN + r*40)
        .endrepeat
row_hi:
        .repeat 25, r
        .byte >(SCREEN + r*40)
        .endrepeat

name_off:
        .repeat NPARAMS, i
        .byte i*10
        .endrepeat
param_names:
        scrcode "waveform  "
        scrcode "attack    "
        scrcode "decay     "
        scrcode "sustain   "
        scrcode "release   "
        scrcode "pulse wid "
        scrcode "filter    "
        scrcode "cutoff    "
        scrcode "resonance "
        scrcode "octave    "

wave_off:
        .byte 0, 5, 10, 15
wave_names:
        scrcode "tri  "
        scrcode "saw  "
        scrcode "pulse"
        scrcode "noise"
fmode_off:
        .byte 0, 5, 10, 15
fmode_names:
        scrcode "off  "
        scrcode "low  "
        scrcode "band "
        scrcode "high "

note_names:
        scrcode "c-c#d-d#e-f-f#g-g#a-a#b-"

.macro STR lbl, text
lbl:    scrcode text
        .byte 0
.endmacro

        STR s_title, "sid piano - commodore 64 pal"
        STR s_param, "parameter   value"
        STR s_voices, "voices"
        STR s_v1, "1:"
        STR s_v2, "2:"
        STR s_v3, "3:"
        STR s_black_up, "2 3   5 6 7"
        STR s_white_up, "q w e r t y u i"
        STR s_black_low, "s d   g h j"
        STR s_white_low, "z x c v b n m ,"
        STR s_oct_up, "octave + 1"
        STR s_oct_low, "octave"
        STR s_help1, "f1 tri f3 saw f5 pulse f7 noise"
        STR s_help2, "+/- octave crsr edit stop quit"

; --- variables --------------------------------------------------------------------

        .segment "BSS"

keys:       .res 8              ; keyboard matrix now
prev:       .res 8              ; ... and in the previous frame
pk:         .res NKEYS          ; piano keys down
param_val:  .res NPARAMS
voicekey:   .res 3              ; piano key on each voice, $FF = free
voicenote:  .res 3              ; semitone each voice is playing
nextvoice:  .res 1
sel:        .res 1              ; selected parameter
shiftflag:  .res 1
repeat:     .res 1
quit:       .res 1
dirty:      .res 1              ; the screen needs a redraw
patchdirty: .res 1              ; the SID needs the patch again
ctrlbits:   .res 1              ; waveform bits of the control register
ad_val:     .res 1
sr_val:     .res 1
fl:         .res 1
fh:         .res 1
vtmp:       .res 1
tmp:        .res 1
pidx:       .res 1
old_irq:    .res 2
