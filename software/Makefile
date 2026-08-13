#===============================================================================
# Makefile
# TinyRISC-TinyML -- builds TWO firmware images:
#   firmware_sw.hex  (Version 1, -DVERSION_SOFTWARE, links software_nn.c)
#   firmware_hw.hex  (Version 2, -DVERSION_HARDWARE, links accelerator_driver.c)
#
# Build rules/flags follow PicoRV32's own top-level Makefile pattern
# (picorv32-1.0/Makefile) as closely as possible -- same reasoning as
# reusing picorv32.v and simpleuart.v themselves: proven conventions,
# less risk of a subtle toolchain-flag mistake.
#
# main.c is compiled TWICE, once per version, each with its matching
# -DVERSION_* define (see main.c's #if/#elif guard) -- uart.o and timer.o
# are the only object files genuinely shared between the two images.
#
# Usage:
#   make            builds both firmware_sw.hex and firmware_hw.hex
#   make sw         builds only firmware_sw.hex
#   make hw         builds only firmware_hw.hex
#   make clean
#
# TOOLCHAIN_PREFIX: override on the command line if your toolchain uses a
# different prefix, e.g.:
#   make TOOLCHAIN_PREFIX=riscv32-unknown-elf-
#===============================================================================

TOOLCHAIN_PREFIX ?= riscv64-unknown-elf-
CC      = $(TOOLCHAIN_PREFIX)gcc
OBJCOPY = $(TOOLCHAIN_PREFIX)objcopy

# -march=rv32i (no M/C extension) matches PicoRV32's default instantiation
# parameters (ENABLE_MUL=0, ENABLE_DIV=0, COMPRESSED_ISA=0 -- see
# picorv32.v). This is the SAFE choice: it works whether or not Phase 6's
# soc_top.v ends up enabling the hardware multiplier, since GCC falls back
# to libgcc software-multiply routines (`-lgcc`, linked below) when the
# target ISA doesn't include M. If Phase 6 enables ENABLE_MUL=1, change
# this to rv32im for a faster (but no longer maximally portable) Version 1
# build.
ARCH = rv32i

INCLUDES = -Iinclude -I../generated/software

GCC_WARNS  = -Wall -Wextra -Wshadow -Wundef -Wpointer-arith -Wcast-qual
GCC_WARNS += -Wcast-align -Wwrite-strings -Wredundant-decls
GCC_WARNS += -Wstrict-prototypes -Wmissing-prototypes

CFLAGS  = -march=$(ARCH) -mabi=ilp32 -Os --std=c99 $(GCC_WARNS) $(INCLUDES)
CFLAGS += -ffreestanding -nostdlib
ASFLAGS = -march=$(ARCH) -mabi=ilp32

# Number of 32-bit words in the RAM region, per linker/sections.lds
# (LENGTH = 0x8000 bytes / 4 = 8192 words). Keep in sync if sections.lds's
# RAM_SIZE ever changes.
RAM_WORDS = 8192

MAKEHEX = python3 ../tools/scripts/makehex.py

.PHONY: all sw hw clean
all: sw hw

# ---- Version 1 (software) ----
sw: firmware_sw.hex

firmware_sw.hex: firmware_sw.bin
	$(MAKEHEX) $< $(RAM_WORDS) > $@

firmware_sw.bin: firmware_sw.elf
	$(OBJCOPY) -O binary $< $@
	chmod -x $@

firmware_sw.elf: linker/start.o src/main_sw.o src/uart.o src/timer.o src/software_nn.o linker/sections.lds
	$(CC) $(CFLAGS) -o $@ \
		-Wl,-Bstatic,-T,linker/sections.lds,-Map,firmware_sw.map,--strip-debug \
		linker/start.o src/main_sw.o src/uart.o src/timer.o src/software_nn.o -lgcc
	chmod -x $@

# ---- Version 2 (hardware accelerator) ----
hw: firmware_hw.hex

firmware_hw.hex: firmware_hw.bin
	$(MAKEHEX) $< $(RAM_WORDS) > $@

firmware_hw.bin: firmware_hw.elf
	$(OBJCOPY) -O binary $< $@
	chmod -x $@

firmware_hw.elf: linker/start.o src/main_hw.o src/uart.o src/timer.o src/accelerator_driver.o linker/sections.lds
	$(CC) $(CFLAGS) -o $@ \
		-Wl,-Bstatic,-T,linker/sections.lds,-Map,firmware_hw.map,--strip-debug \
		linker/start.o src/main_hw.o src/uart.o src/timer.o src/accelerator_driver.o -lgcc
	chmod -x $@

# ---- main.c built once per version, with the matching -DVERSION_* define ----
src/main_sw.o: src/main.c
	$(CC) -c $(CFLAGS) -DVERSION_SOFTWARE -o $@ $<

src/main_hw.o: src/main.c
	$(CC) -c $(CFLAGS) -DVERSION_HARDWARE -o $@ $<

# ---- everything else: one object file per source file, shared as-is ----
src/%.o: src/%.c
	$(CC) -c $(CFLAGS) -o $@ $<

linker/start.o: linker/start.S
	$(CC) -c $(ASFLAGS) -o $@ $<

clean:
	rm -f src/*.o linker/*.o
	rm -f firmware_sw.elf firmware_sw.bin firmware_sw.hex firmware_sw.map
	rm -f firmware_hw.elf firmware_hw.bin firmware_hw.hex firmware_hw.map
