# --- Commodore 64 ---------------------------------------------------------------
#   make c64              build c64/hello.s -> build/hello-c64.prg
#   make c64-run          open it in VICE

X64     ?= x64sc

c64: build/hello-c64.prg

build/hello-c64.prg: c64/hello.s
	@mkdir -p build
	ca65 -t c64 -l build/hello-c64.lst -o build/hello-c64.o $<
	ld65 -C c64-asm.cfg -u __EXEHDR__ -o $@ build/hello-c64.o c64.lib
	@echo "Built $@ ($$(wc -c < $@ | tr -d ' ') bytes)"

# Shared I/O for the programs in apps/ (KERNAL CHRIN / CHROUT)
C64_IO := build/c64/io.o

$(C64_IO): c64/io.s
	@mkdir -p $(@D)
	ca65 -t c64 -l $(@:.o=.lst) -o $@ $<

# open a .prg in VICE: x64sc from the PATH, else the macOS app
vice = @if command -v $(X64) >/dev/null; then $(X64) -autostart $(abspath $(1)); \
	 else open -a x64sc --args -autostart "$(abspath $(1))"; fi

c64-run: build/hello-c64.prg
	$(call vice,$<)

.PHONY: c64 c64-run
