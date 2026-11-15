# --- Chiplab 6502 board -------------------------------------------------------
#   make                  build chiplab/hello.s  -> build/hello.bin
#   make run / trace      run it on the board (trace: every bus cycle)
#   make trace-asm        same, one disassembled line per instruction,
#                         written to build/$(PROG).asm-trace.txt
#   make trace-bin BIN=build/calc.bin [CYCLES=0]
#                         disassembled trace of any Chiplab image, written
#                         next to it (build/calc.asm-trace.txt)
#   make run PROG=foo     build and run chiplab/foo.s instead
#   make ports            list the serial ports

PROG    ?= hello
PORT    ?= auto
CYCLES  ?= 2000
CHIPLAB_CFG := chiplab/chiplab.cfg

# Single-file programs in chiplab/
build/%.o: chiplab/%.s
	@mkdir -p build
	ca65 --cpu 65C02 -g -l build/$*.lst -o $@ $<

build/%.bin: build/%.o $(CHIPLAB_CFG)
	ld65 -C $(CHIPLAB_CFG) -m build/$*.map -Ln build/$*.lbl -o $@ $<
	@echo "Built $@ ($$(wc -c < $@ | tr -d ' ') bytes)"

# Shared I/O for the programs in apps/ (keyboard, console, exit, reset)
CHIPLAB_IO := build/chiplab/io.o

$(CHIPLAB_IO): chiplab/io.s
	@mkdir -p $(@D)
	ca65 --cpu 65C02 -g -l $(@:.o=.lst) -o $@ $<

run: build/$(PROG).bin $(PY)
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles $(CYCLES) $<

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
