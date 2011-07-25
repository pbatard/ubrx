#
# This file is part of the UBRX project.
#
# Copyright (c) 2011 Pete Batard <pbatard@akeo.ie>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of
# the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <http://www.gnu.org/licenses/>.
#

# You can modify the 2 variables below according to your needs.
# Note: these can also be overridden from the shell.
# Size of the BIOS chip (not case sensitive)
ROM_SIZE  ?= 512K
# Size of the bootblock payload (case sensitive)
BB_SIZE   ?= 8K

OBJECTS   = bios.o console.o
TARGET    = bios
MEMLAYOUT = xMemLayout.map

ASM       = gcc
CC        = gcc
LD        = ld
OBJDUMP   = objdump
OBJCOPY   = objcopy
CFLAGS    = -m32
LDFLAGS   = -nostartfile

# For the flashrom bootblock layout
ifeq ($(BB_SIZE), 4K)
	BB_START_HEX = f000
endif
ifeq ($(BB_SIZE), 8K)
	BB_START_HEX = e000
endif
ifeq ($(BB_SIZE), 16K)
	BB_START_HEX = c000
endif
ifeq ($(BB_SIZE), 32K)
	BB_START_HEX = 8000
endif
ifeq ($(BB_SIZE), 64K)
	BB_START_HEX = 0000
endif

.PHONY: all clean $(TARGET).ld vmware erase dis flash p5b 128k 256k 512k 1m 2m

all: $(TARGET).rom

clean:
	@-rm -f -v *.o *.ld *.layout $(TARGET).out $(MEMLAYOUT)

# Common flash sizes. Note that we can't use $@ in the target-specific variable
# line as ROM_SIZE would be evaluated to the target at hand when reused.
128k: ROM_SIZE=128k
128k: $(TARGET).rom
	@# Generate a flashrom layout so that only the bootblock can be flashed
	@echo "0001$(BB_START_HEX):0001ffff bootblock" > $@.layout

256k: ROM_SIZE=256k
256k: $(TARGET).rom
	@echo "0003$(BB_START_HEX):0003ffff bootblock" > $@.layout

512k: ROM_SIZE=512k
512k: $(TARGET).rom
	@echo "0007$(BB_START_HEX):0007ffff bootblock" > $@.layout

1m: ROM_SIZE=1m
1m: $(TARGET).rom
	@echo "000f$(BB_START_HEX):000fffff bootblock" > $@.layout

2m: ROM_SIZE=2m
2m: $(TARGET).rom
	@echo "001f$(BB_START_HEX):001fffff bootblock" > $@.layout

# Build a 512 KB BIOS for VMware, copy it and erase existing serial output
vmware: 512k
	@cp $(TARGET).rom /e/VMware/BIOS
	@rm -f /e/VMware/BIOS/com.txt

# Flash/Erase a 128 KB BIOS using flashrom against a RealTek NIC
flash: 128k
	@# Use the layout feature of flashrom to flash only the bootblock
	@flashrom -p nicrealtek -l 128k.layout -i bootblock -n -w $(TARGET).rom

erase:
	@flashrom -p nicrealtek -E

# Flash a 1MB BIOS on an ASUS P5B motherboard through SPI through, using an FT2232 USB adapter
p5b: 1m
	flashrom -p ft2232_spi:type=arm-usb-tiny -l 1m.layout -i bootblock -n -w $(TARGET).rom

%.o: %.c Makefile
	@echo "[CC]  $@"
	@$(CC) -c -o $*.o $(CFLAGS) $<

%.o: %.S Makefile mmx_stack.inc
	@echo "[AS]  $<"
	@$(ASM) -c -o $*.o $(CFLAGS) $<

# Produce a disassembly dump of the main section, for verification purposes
dis: $(TARGET).out
	@echo "[DIS] $<"
	@$(OBJCOPY) -O binary -j .main --set-section-flags .main=alloc,load,readonly,code $< main.bin
	@$(OBJDUMP) -D -bbinary -mi8086 -Mintel main.bin | less
	@-rm -f main.bin

$(TARGET).ld:
	@# external constants are foreign to ld scripts and Makefile doesn't like multiline. Oh well...
	@echo "OUTPUT_ARCH(i8086)" > $(ROM_SIZE).ld
	@echo "main_address = 4096M - $(BB_SIZE);" >> $(ROM_SIZE).ld
	@echo "MEMORY { ROM (rx) : org = 4096M - $(ROM_SIZE), len = $(ROM_SIZE) }" >> $(ROM_SIZE).ld
	@echo "SECTIONS {" >> $(ROM_SIZE).ld
	@echo "	ENTRY(init)" >> $(ROM_SIZE).ld
	@echo "	_assert = ASSERT(init >= 4096M - 64K, \"'init' entrypoint too low - it needs to reside in the last 64K.\");" >> $(ROM_SIZE).ld
	@echo "	.begin : { *(begin) } >ROM" >> $(ROM_SIZE).ld
	@echo "	.main main_address : { *(main) *(console) }" >> $(ROM_SIZE).ld
	@echo "	.reset 4096M - 0x10 : {	*(reset) }" >> $(ROM_SIZE).ld
	@echo "	.igot 0 : { *(.igot.plt) }" >> $(ROM_SIZE).ld
	@echo "}" >> $(ROM_SIZE).ld

$(TARGET).out: $(OBJECTS) $(TARGET).ld
	@echo "[LD]  $@"
	@$(LD) $(LDFLAGS) -T$(ROM_SIZE).ld -o $@ $(OBJECTS) -Map $(MEMLAYOUT)

$(TARGET).rom: $(TARGET).out
	@echo "[ROM] $@"
	@# Note: -j only works for sections that have the 'ALLOC' flag set
	@$(OBJCOPY) -O binary -j .begin -j .main -j .reset --gap-fill=0x0ff $< $@
