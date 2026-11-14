# --- Apple I (in MAME) ---------------------------------------------------------
#   make apple1           build apple1/hello.s, print it as Woz Monitor hex
#   make apple1-sim       quick check in the terminal (tools/apple1_sim.py)
#   make apple1-run       type it into MAME's Apple I
#   make apple1-snap      same, loaded instantly from a snapshot
#   make basic-run        Apple I BASIC (needs apple1/basic.bin)
#   make basic-prog PROG=apple1/programs/HAMURABI.txt
#   make woz-prog   PROG=apple1/programs/life.txt RUN=2000
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

# --- Apple I BASIC ---------------------------------------------------------------
# Put your 4096-byte BASIC image at apple1/basic.bin, or pass BASIC=path.
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

.PHONY: apple1 apple1-sim apple1-run basic-run apple1-snap basic-prog woz-prog
