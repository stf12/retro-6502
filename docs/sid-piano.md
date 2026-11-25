# SID piano (Commodore 64, PAL)

A live instrument for the C64: the keyboard plays the SID, a small screen edits the sound.
Source: `apps/sidpiano/sidpiano.s`. Build with `make sidpiano`, try it with `make sidpiano-run`
(VICE) or copy `build/sidpiano.prg` to the real machine and `RUN` it.

## Keys

| Keys | Action |
|------|--------|
| `z s x d c v g b h n j m ,` | lower octave, 13 notes (`s d g h j` are the black keys) |
| `q 2 w 3 e r 5 t 6 y 7 u i` | the octave above, 13 notes (`2 3 5 6 7` are the black keys) |
| `f1` `f3` `f5` `f7` | triangle, sawtooth, pulse, noise |
| `+` `-` | octave up / down (0-5) |
| cursor up / down | select a parameter (with SHIFT: the other way) |
| cursor left / right | change it, with auto repeat (with SHIFT: the other way) |
| `run/stop` | back to BASIC |

Up to three notes sound at once, one per SID voice, all with the same patch. A fourth key is
ignored until a voice is free.

Editable parameters: waveform, attack, decay, sustain, release, pulse width, filter mode
(off / low / band / high), cutoff, resonance, octave.

## How it works

- **Keyboard**: the CIA1 key matrix is scanned directly (`$DC00` selects a column, `$DC01` reads
  the rows). Unlike the KERNAL (`GETIN`) this sees every key that is down, so chords and key
  releases work.
- **Timing**: a raster IRQ at line 250 replaces the KERNAL IRQ and runs once per PAL frame
  (50 Hz). It scans the keys, handles the controls and writes the SID. The KERNAL keyboard scan is
  skipped (the handler exits through `$EA81`). The main loop only redraws the screen when
  something changed.
- **Pitch**: the PAL SID frequency register is `Hz * 2^24 / 985248`. The table holds the twelve
  notes of octave 7; lower octaves are the same value shifted right. A4 = 440 Hz is within 0.03 Hz.
- **Voices**: each pressed key takes a free voice (round robin, so a voice that just entered its
  release phase is not retriggered immediately). Releasing the key clears the gate bit.
- **Exit**: `run/stop` stops the raster IRQ, silences the SID and calls the KERNAL
  `IOINIT`, `RESTOR` and `CINT` routines, then returns to BASIC.

## Testing without hardware

The program was checked in a py65 simulation with a fake CIA key matrix and a logged SID: note
frequencies in several octaves, three-note chords, voice release, waveform keys, octave limits,
parameter selection and auto repeat, filter bits and the drawn screen. It has not been run on a
real C64 or in VICE yet.

## Next steps

- 2 octave piano picture that lights up the pressed keys.
- A tracker: three columns of notes in a pattern, played by the same IRQ.
- Vibrato, pulse width modulation and a filter sweep driven by the IRQ.
