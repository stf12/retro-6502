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

clean:
	rm -rf build

.PHONY: all run trace ports setup clean c64 c64-run calc calc-c64 calc-run calc-c64-run
.PRECIOUS: build/%.o
