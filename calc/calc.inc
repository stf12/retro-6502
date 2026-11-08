; ---------------------------------------------------------------------------
; calc.inc - shared definitions for the 16-bit calculator
;
; All numbers are 16-bit UNSIGNED (0-65535), stored little-endian:
;   num1 = low byte, num1+1 = high byte
; ---------------------------------------------------------------------------

CR      = $0D                   ; RETURN key / end of input line
ptr     = $FB                   ; 2 zero-page bytes for (ptr),y
                                ; ($FB-$FC are free for users on the C64)

; --- platform I/O: io_chiplab.s or io_c64.s, same names on both -------------
.import io_getc                 ; A = next input character (line-buffered,
                                ;     the line ends with CR)
.import io_putc                 ; print the character in A (keeps X and Y)
.import io_newline              ; start a new output line
.import io_quit                 ; leave the program
