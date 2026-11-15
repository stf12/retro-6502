# --- Calculator: same sources, two machines -----------------------------------
#   make calc / calc-run          Chiplab: build/calc.bin, run on the board
#   make calc-c64 / calc-c64-run  C64: build/calc-c64.prg, open in VICE
#
# Portable code lives here; the machine I/O comes from chiplab/io.s or
# c64/io.s (CHIPLAB_IO / C64_IO, defined in their .mk files).
# calc.s must come first: on the C64, BASIC's SYS jumps to its first byte.

CALC_DIR     := apps/calc
CALC_SRC     := calc.s math16.s numio.s
CALC_CHIPLAB := $(addprefix build/calc/chiplab/,$(CALC_SRC:.s=.o)) $(CHIPLAB_IO)
CALC_C64     := $(addprefix build/calc/c64/,$(CALC_SRC:.s=.o)) $(C64_IO)

build/calc/chiplab/%.o: $(CALC_DIR)/%.s $(CALC_DIR)/calc.inc
	@mkdir -p $(@D)
	ca65 --cpu 65C02 -g -I $(CALC_DIR) -l $(@:.o=.lst) -o $@ $<

build/calc/c64/%.o: $(CALC_DIR)/%.s $(CALC_DIR)/calc.inc
	@mkdir -p $(@D)
	ca65 -t c64 -I $(CALC_DIR) -l $(@:.o=.lst) -o $@ $<

build/calc.bin: $(CALC_CHIPLAB) $(CHIPLAB_CFG)
	ld65 -C $(CHIPLAB_CFG) -m build/calc.map -Ln build/calc.lbl -o $@ $(CALC_CHIPLAB)
	@echo "Built $@"

build/calc-c64.prg: $(CALC_C64)
	ld65 -C c64-asm.cfg -u __EXEHDR__ -m build/calc-c64.map -o $@ $(CALC_C64) c64.lib
	@echo "Built $@ ($$(wc -c < $@ | tr -d ' ') bytes)"

calc: build/calc.bin
calc-c64: build/calc-c64.prg

calc-run: build/calc.bin $(PY)
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles 0 $<

calc-trace-asm: build/calc.bin $(PY)
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles 0 --trace-asm \
	  --trace-out build/calc.asm-trace.txt $<

calc-c64-run: build/calc-c64.prg
	$(call vice,$<)

calc-trace: build/calc.bin $(PY)
	$(PY) tools/chiplab_run.py --port $(PORT) --cycles 0 --trace $<

.PHONY: calc calc-c64 calc-run calc-trace calc-trace-asm calc-c64-run
