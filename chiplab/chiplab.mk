# --- Chiplab 6502 board -------------------------------------------------------
#   make                  build chiplab/hello.s  -> build/hello.bin
#   make run / trace      run it on the board (trace: every bus cycle)
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
	ca65 --cpu 65C02 -l $(@:.o=.lst) -o $@ $<

run: build/$(PROG).bin $(PY)
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles $(CYCLES) $<

trace: build/$(PROG).bin $(PY)
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles $(CYCLES) --trace $<

ports: $(PY)
	$(PY) -m serial.tools.list_ports -v

.PHONY: run trace ports
