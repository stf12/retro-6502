# --- Chiplab board firmware (ATmega32U4) ----------------------------------------
# The board identifies as an Arduino Micro (arduino:avr:micro) with the
# Caterina USB bootloader: new firmware goes in over the normal USB cable.
#
#   make fw-build                 compile firmware/6502_pcb with arduino-cli
#   make fw-upload                compile and upload it to the board
#   make fw-backup                read the whole flash into firmware/backup/
#   make fw-restore FILE=firmware/backup/xxx.hex
#                                 write a backup back (firmware part only)
#
# Needs: brew install arduino-cli avrdude ; arduino-cli core install arduino:avr
# The port is found automatically; override with FW_PORT=/dev/cu.usbmodemXXXX

FQBN      ?= arduino:avr:micro
FW_SKETCH := firmware/6502_pcb
FW_BUILD  := build/firmware
FW_PORT   ?= $(firstword $(wildcard /dev/cu.usbmodem*))

fw-port-check = @test -n "$(FW_PORT)" || \
	{ echo "No board found (/dev/cu.usbmodem*): plug it in, or pass FW_PORT=..."; exit 1; }

# Restart the board into its bootloader with the "1200 baud touch", then set
# BOOT to the bootloader's port (sometimes it gets a different name).
# The bootloader waits about 8 seconds: the avrdude call must follow at once.
fw-bootloader = \
	ls /dev/cu.usbmodem* > build/ports-before.txt 2>/dev/null; \
	$(PY) -c "import serial; serial.Serial('$(FW_PORT)', 1200).close()" || exit 1; \
	sleep 2; \
	BOOT=$$(ls /dev/cu.usbmodem* 2>/dev/null | grep -vxFf build/ports-before.txt | head -1); \
	BOOT=$${BOOT:-$(FW_PORT)}; \
	echo "bootloader on $$BOOT"

fw-build:
	arduino-cli compile --fqbn $(FQBN) --output-dir $(FW_BUILD) $(FW_SKETCH)

# arduino-cli does the 1200 baud touch by itself for the Micro.
# -v shows avrdude's full output; --verify reads the flash back and compares.
# Afterwards, check that the new firmware comes back on USB: once (2026-11)
# the board stayed stuck after a good upload until a reset.
fw-upload: fw-build
	$(fw-port-check)
	arduino-cli upload -v --verify --fqbn $(FQBN) -p $(FW_PORT) --input-dir $(FW_BUILD) $(FW_SKETCH)
	@echo "Waiting for the board to come back..."; sleep 3; \
	for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do \
	  if ls /dev/cu.usbmodem* >/dev/null 2>&1; then \
	    echo "Board is back on $$(ls /dev/cu.usbmodem* | head -1)"; exit 0; fi; \
	  sleep 0.5; done; \
	echo "The board did not come back on USB. The upload itself may be fine:"; \
	echo "unplug the cable for 10 seconds, or tap RESET to GND on the 6-pin"; \
	echo "header (its first and last pin), then run: ls /dev/cu.usbmodem*"; exit 1

fw-backup: $(PY)
	$(fw-port-check)
	@mkdir -p build firmware/backup
	@$(fw-bootloader); \
	avrdude -p atmega32u4 -c avr109 -P "$$BOOT" \
	  -U flash:r:firmware/backup/flash-$$(date +%Y%m%d-%H%M%S).hex:i

# A backup also holds the bootloader ($7000-$7FFF), which the chip protects
# from being overwritten: only the firmware part ($0000-$6FFF) is written.
fw-restore: $(PY)
	$(fw-port-check)
	@test -n "$(FILE)" || \
	  { echo "usage: make fw-restore FILE=firmware/backup/flash-....hex"; exit 1; }
	@mkdir -p build
	python3 tools/hex_app_only.py $(FILE) build/firmware-restore.hex
	@$(fw-bootloader); \
	avrdude -p atmega32u4 -c avr109 -P "$$BOOT" -U flash:w:build/firmware-restore.hex:i

.PHONY: fw-build fw-upload fw-backup fw-restore
