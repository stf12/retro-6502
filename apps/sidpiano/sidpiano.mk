# --- SID piano: a live SID instrument for the C64 (PAL) -----------------------
#   make sidpiano       build/sidpiano.prg
#   make sidpiano-run   open it in VICE
#
# Commodore 64 only: it plays the SID chip and reads the keyboard matrix.

build/sidpiano.prg: apps/sidpiano/sidpiano.s
	@mkdir -p build
	ca65 -t c64 -l build/sidpiano.lst -o build/sidpiano.o $<
	ld65 -C c64-asm.cfg -u __EXEHDR__ -m build/sidpiano.map -o $@ build/sidpiano.o c64.lib
	@echo "Built $@ ($$(wc -c < $@ | tr -d ' ') bytes)"

sidpiano: build/sidpiano.prg

sidpiano-run: build/sidpiano.prg
	$(call vice,$<)

.PHONY: sidpiano sidpiano-run
