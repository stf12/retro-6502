# Chiplab 6502 build — `make`, `make run`, `make setup`
PROG    ?= hello
PORT    ?= auto
CYCLES  ?= 2000
PY      := .venv/bin/python

all: build/$(PROG).bin

build/%.o: src/%.s
	@mkdir -p build
	ca65 --cpu 65C02 -g -l build/$*.lst -o $@ $<

build/%.bin: build/%.o chiplab.cfg
	ld65 -C chiplab.cfg -m build/$*.map -Ln build/$*.lbl -o $@ $<
	@echo "Built $@ ($$(wc -c < $@ | tr -d ' ') bytes)"

run: build/$(PROG).bin $(PY)
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles $(CYCLES) $<

trace: build/$(PROG).bin $(PY)
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles $(CYCLES) --trace $<

ports: $(PY)
	$(PY) -m serial.tools.list_ports -v

setup: $(PY)

$(PY):
	python3 -m venv .venv
	.venv/bin/pip install --quiet pyserial

# --- Commodore 64 -----------------------------------------------------------
X64     ?= x64sc

c64: build/hello-c64.prg

build/hello-c64.prg: c64/hello.s
	@mkdir -p build
	ca65 -t c64 -l build/hello-c64.lst -o build/hello-c64.o $<
	ld65 -C c64-asm.cfg -u __EXEHDR__ -o $@ build/hello-c64.o c64.lib
	@echo "Built $@ ($$(wc -c < $@ | tr -d ' ') bytes)"

# open a .prg in VICE: x64sc from the PATH, else the macOS app
vice = @if command -v $(X64) >/dev/null; then $(X64) -autostart $(abspath $(1)); \
	 else open -a x64sc --args -autostart "$(abspath $(1))"; fi

c64-run: build/hello-c64.prg
	$(call vice,$<)

# --- Calculator: same sources, two machines ----------------------------------
# calc.s must come first: on the C64, BASIC's SYS jumps to its first byte.
CALC_SRC     := calc.s math16.s numio.s
CALC_CHIPLAB := $(addprefix build/calc/chiplab/,$(CALC_SRC:.s=.o) io_chiplab.o)
CALC_C64     := $(addprefix build/calc/c64/,$(CALC_SRC:.s=.o) io_c64.o)

build/calc/chiplab/%.o: calc/%.s calc/calc.inc
	@mkdir -p $(@D)
	ca65 --cpu 65C02 -I calc -l $(@:.o=.lst) -o $@ $<

build/calc/c64/%.o: calc/%.s calc/calc.inc
	@mkdir -p $(@D)
	ca65 -t c64 -I calc -l $(@:.o=.lst) -o $@ $<

build/calc.bin: $(CALC_CHIPLAB) chiplab.cfg
	ld65 -C chiplab.cfg -m build/calc.map -Ln build/calc.lbl -o $@ $(CALC_CHIPLAB)
	@echo "Built $@"

build/calc-c64.prg: $(CALC_C64)
	ld65 -C c64-asm.cfg -u __EXEHDR__ -m build/calc-c64.map -o $@ $(CALC_C64) c64.lib
	@echo "Built $@ ($$(wc -c < $@ | tr -d ' ') bytes)"

calc: build/calc.bin
calc-c64: build/calc-c64.prg

calc-run: build/calc.bin $(PY)
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles 0 $<

calc-c64-run: build/calc-c64.prg
	$(call vice,$<)
# ---------------------------------------------------------------------------
# Apple I 
# ---------------------------------------------------------------------------
MAME         ?= mame
MAME_ROMPATH ?= $(HOME)/Applications/mame/roms

build/hello-apple1.bin: apple1/hello.s apple1/apple1.cfg
	@mkdir -p build
	ca65 -l build/hello-apple1.lst -o build/hello-apple1.o $<
	ld65 -C apple1/apple1.cfg -m build/hello-apple1.map -o $@ build/hello-apple1.o
	@echo "Built $@ ($$(wc -c < $@ | tr -d ' ') bytes)"

build/hello-apple1.woz: build/hello-apple1.bin tools/bin2woz.py
	python3 tools/bin2woz.py $< -o $@

apple1: build/hello-apple1.bin build/hello-apple1.woz
	@cat build/hello-apple1.woz

apple1-sim: build/hello-apple1.bin $(PY)
	$(PY) tools/apple1_sim.py $<

apple1-run: build/hello-apple1.bin
	$(MAME) apple1 -rompath "$(MAME_ROMPATH)" -window -skip_gameinfo -ui_active \
	  -autoboot_delay 3 \
	  -autoboot_command "$$(python3 tools/bin2woz.py $< --mame)"

# ---------------------------------------------------------------------------
# Apple I BASIC in MAME -- paste ABOVE "clean:" (after the Apple I block).
# Put your 4096-byte BASIC image at apple1/basic.bin, or pass BASIC=path.
# ---------------------------------------------------------------------------
BASIC ?= apple1/basic.bin
# MAME's apple1 snapshot loader has an off-by-one: a load ending at $EFFF is
# rejected. We load $E000-$EFFE and type the last byte in the Woz Monitor.
BASIC_LAST = $$(tail -c 1 $(BASIC) | od -An -tx1 | tr -d ' \n' | tr a-f A-F)

build/basic.snp: $(BASIC) tools/bin2snp.py
	@mkdir -p build
	python3 tools/bin2snp.py $< --addr 0xE000 --trim-last -o $@

basic-run: build/basic.snp
	$(MAME) apple1 -rompath "$(MAME_ROMPATH)" -window -skip_gameinfo -ui_active \
	  -snapshot $(abspath $<) -autoboot_delay 2 -autoboot_command "\nEFFF: $(BASIC_LAST)\nE000R\n"

# Bonus: hello world via snapshot, instant instead of "typed" in
build/hello-apple1.snp: build/hello-apple1.bin tools/bin2snp.py
	python3 tools/bin2snp.py $< -o $@

apple1-snap: build/hello-apple1.snp
	$(MAME) apple1 -rompath "$(MAME_ROMPATH)" -window -skip_gameinfo -ui_active \
	  -snapshot $(abspath $<) -autoboot_delay 2 -autoboot_command '\n280R\n'

# ...and add  basic-run apple1-snap  to the .PHONY line

# ---------------------------------------------------------------------------
# Type a whole program into the Apple I, ONE LINE AT A TIME (MAME Lua script).
#   BASIC listing:    make basic-prog PROG=apple1/programs/HAMURABI.txt
#   Woz Monitor hex:  make woz-prog  PROG=apple1/programs/life.txt RUN=2000
# LINE_DELAY = pause after each line in frames (60 = 1 s). If characters
# still get lost, try  make basic-prog ... LINE_DELAY=40
# ---------------------------------------------------------------------------
LINE_DELAY ?= 40

basic-prog: build/basic.snp
	python3 tools/txt2lua.py $(PROG) -o build/autotype.lua --delay $(LINE_DELAY) \
	  --pre "EFFF: $(BASIC_LAST)" --pre E000R --post RUN
	$(MAME) apple1 -rompath "$(MAME_ROMPATH)" -window -skip_gameinfo -ui_active \
	  -snapshot $(abspath $<) -autoboot_script build/autotype.lua

woz-prog:
	@mkdir -p build
	python3 tools/txt2lua.py $(PROG) -o build/autotype.lua --delay $(LINE_DELAY) --post $(RUN)R
	$(MAME) apple1 -rompath "$(MAME_ROMPATH)" -window -skip_gameinfo -ui_active \
	  -autoboot_script build/autotype.lua

clean:
	rm -rf build

.PHONY: all run trace ports setup clean c64 c64-run calc calc-c64 calc-run calc-c64-run apple1 apple1-sim apple1-run basic-run apple1-snap basic-prog woz-prog
.PRECIOUS: build/%.o
