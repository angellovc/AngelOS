NASM ?= nasm
QEMU ?= qemu-system-i386

# Code guide: lessons/02-stage2-loader.md explains how these rules turn the two
# independently assembled binaries into one disk image.

BUILD_DIR := build
BOOT_BIN := $(BUILD_DIR)/boot.bin
STAGE2_BIN := $(BUILD_DIR)/stage2.bin
OS_IMAGE := $(BUILD_DIR)/os.img

.PHONY: all run run-headless check clean

all: $(OS_IMAGE) check

$(BUILD_DIR):
	mkdir -p $@

$(BOOT_BIN): boot/boot.asm | $(BUILD_DIR)
	$(NASM) -f bin -Wall -Werror -o $@ $<

$(STAGE2_BIN): boot/stage2.asm | $(BUILD_DIR)
	$(NASM) -f bin -Wall -Werror -o $@ $<

$(OS_IMAGE): $(BOOT_BIN) $(STAGE2_BIN)
	dd if=/dev/zero of=$@ bs=512 count=2880 status=none
	dd if=$(BOOT_BIN) of=$@ conv=notrunc status=none
	dd if=$(STAGE2_BIN) of=$@ bs=512 seek=1 conv=notrunc status=none

check: $(BOOT_BIN) $(STAGE2_BIN) $(OS_IMAGE)
	@test "$$(wc -c < $(BOOT_BIN) | tr -d ' ')" = 512
	@test "$$(od -An -tx1 -j510 -N2 $(BOOT_BIN) | tr -d ' \n')" = 55aa
	@test "$$(wc -c < $(STAGE2_BIN) | tr -d ' ')" = 2048
	@test "$$(wc -c < $(OS_IMAGE) | tr -d ' ')" = 1474560
	@echo "image OK: boot signature 55 aa; stage 2 is 4 sectors"

run: all
	$(QEMU) -drive format=raw,file=$(OS_IMAGE),if=floppy

run-headless: all
	$(QEMU) -drive format=raw,file=$(OS_IMAGE),if=floppy -display none \
		-debugcon stdio -global isa-debugcon.iobase=0xe9 -no-reboot -no-shutdown

clean:
	rm -rf $(BUILD_DIR)
