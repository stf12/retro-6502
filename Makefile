# retro-6502 — 6502 programs for the Chiplab board, the C64 and the Apple I
#
# The rules live next to what they build:
#   chiplab/chiplab.mk   Chiplab board: hello world, run/trace on the board
#   c64/c64.mk           Commodore 64: hello world, VICE
#   apple1/apple1.mk     Apple I: hello world, BASIC and programs in MAME
#   apps/calc/calc.mk    the calculator, for Chiplab and C64
#   apps/sidpiano/sidpiano.mk  the SID piano, C64 only
#   firmware/firmware.mk firmware for the ATmega32U4 MCU on Chiplab board
#
# Run make from this folder: all paths are relative to it.
# `make` alone builds the Chiplab hello world (build/hello.bin).

PY := .venv/bin/python

include chiplab/chiplab.mk
include c64/c64.mk
include apple1/apple1.mk
include apps/calc/calc.mk
include apps/sidpiano/sidpiano.mk
include firmware/firmware.mk

.DEFAULT_GOAL := all
all: build/$(PROG).bin

# Python environment for the host tools. `make setup` always runs pip, so
# packages added to PY_PACKAGES later reach an existing .venv too.
PY_PACKAGES := pyserial py65 pygame-ce

setup: $(PY)
	.venv/bin/pip install --quiet $(PY_PACKAGES)

$(PY):
	python3 -m venv .venv
	.venv/bin/pip install --quiet $(PY_PACKAGES)

clean:
	rm -rf build

.PHONY: all setup clean
.PRECIOUS: build/%.o
