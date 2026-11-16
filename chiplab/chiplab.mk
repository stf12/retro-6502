# --- Chiplab 6502 board -------------------------------------------------------
#   make                  build chiplab/hello.s  -> build/hello.bin
#   make run / trace      run it on the board (trace: every bus cycle)
#   make trace-asm        same, one disassembled line per instruction,
#                         written to build/$(PROG).asm-trace.txt
#   make trace-bin BIN=build/calc.bin [CYCLES=0]
#                         disassembled trace of any Chiplab image, written
#                         next to it (build/calc.asm-trace.txt)
#   make run PROG=foo     build and run chiplab/foo.s instead
#   make run PROG=gfxtest CYCLES=0 [GFX_PNG=build/screen.png]
#                         graphics test picture (window.s: a Mac-style
#                         window); GFX_PNG also saves the final screen
#   make ports            list the serial ports

PROG    ?= hello
PORT    ?= auto
CYCLES  ?= 2000
CHIPLAB_CFG := chiplab/chiplab.cfg
GFX_PNG ?=
GFX_ARGS = $(if $(GFX_PNG),--gfx-png $(GFX_PNG))

# Libraries for Chiplab programs, interfaces in lib/ (gfx.inc). Packed with
# ar65: ld65 takes from a library only the modules a program uses, so a
# program that draws nothing gets no graphics code.
CHIPLAB_LIB := build/chiplab/chiplab.lib
CHIPLAB_LIB_SRC := chiplab/gfx.s

build/chiplab/%.o: chiplab/%.s lib/gfx.inc
	@mkdir -p $(@D)
	ca65 --cpu 65C02 -g -I lib -l $(@:.o=.lst) -o $@ $<

$(CHIPLAB_LIB): $(patsubst chiplab/%.s,build/chiplab/%.o,$(CHIPLAB_LIB_SRC))
	rm -f $@
	ar65 a $@ $^

# Single-file programs in chiplab/
build/%.o: chiplab/%.s lib/gfx.inc
	@mkdir -p build
	ca65 --cpu 65C02 -g -I lib -l build/$*.lst -o $@ $<

build/%.bin: build/%.o $(CHIPLAB_CFG) $(CHIPLAB_LIB)
	ld65 -C $(CHIPLAB_CFG) -m build/$*.map -Ln build/$*.lbl -o $@ $< $(CHIPLAB_LIB)
	@echo "Built $@ ($$(wc -c < $@ | tr -d ' ') bytes)"

# Shared I/O for the programs in apps/ (keyboard, console, exit, reset)
CHIPLAB_IO := build/chiplab/io.o

# (built by the build/chiplab/%.o rule above)

run: build/$(PROG).bin $(PY)
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles $(CYCLES) $(GFX_ARGS) $<

trace: build/$(PROG).bin $(PY)
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles $(CYCLES) --trace $<

trace-asm: build/$(PROG).bin $(PY)
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles $(CYCLES) --trace-asm \
	  --trace-out build/$(PROG).asm-trace.txt $<

# Any 64 KB Chiplab image, already built. Labels are read from the .lbl file
# next to it, if there is one. The trace is opened in VS Code when the
# `code` command is available.
BIN ?=
trace-bin: $(PY)
	@test -n "$(BIN)" || { echo "usage: make trace-bin BIN=path/to/image.bin [CYCLES=0]"; exit 1; }
	@test -f "$(BIN)" || { echo "$(BIN): no such file (build it first)"; exit 1; }
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles $(CYCLES) --trace-asm \
	  --trace-out $(basename $(BIN)).asm-trace.txt $(BIN)
	@if command -v code >/dev/null; then code $(basename $(BIN)).asm-trace.txt; fi

ports: $(PY)
	$(PY) -m serial.tools.list_ports -v

.PHONY: run trace trace-asm trace-bin ports
