/********************************************************************************/
/* UBRX - Universal BIOS Recovery console for X86 ('panic room' bootblock)      */
/*                                                                              */
/* Copyright (c) 2011 Pete Batard <pete@akeo.ie>                                */
/*                                                                              */
/* This program is free software; you can redistribute it and/or modify it      */
/* under the terms of the GNU General Public License as published by the Free   */
/* Software Foundation, either version 3 of the License, or (at your option)    */
/* any later version.                                                           */
/*                                                                              */
/* This program is distributed in the hope that it will be useful, but WITHOUT  */
/* ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or        */
/* FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for    */
/* more details.                                                                */
/*                                                                              */
/* You should have received a copy of the GNU General Public License along with */
/* this program; if not, see <http://www.gnu.org/licenses/>.                    */
/*                                                                              */
/********************************************************************************/

.include "mmx_stack.inc"

/********************************************************************************/
/* GNU Assembler Settings:                                                      */
/********************************************************************************/
.intel_syntax noprefix	# Use Intel assembler syntax (same as IDA Pro)
.code16			# After reset, the x86 CPU is in real/16 bit mode
/********************************************************************************/


/********************************************************************************/
/* Notes:                                                                       */
/********************************************************************************/
/* MMX is required as we use the MMX registers as elementary stack + globals:   */
/* MM0 = pointer to SuperIO base address to test                                */
/* MM4+MM5 = up to 8 word registers stack, or 4 long registers                  */
/* MM6 = up to 4 SP registers stack (return addresses)                          */
/* MM7 = used during stack operations (but free to use otherwise)               */
/* EBP = used for POPXD operations to preserve the content of extended register */
/* If there's any register you don't want to be modified during a call, it is   */
/* your responsibility to PUSHX/POPX them                                       */


/********************************************************************************/
/* Build variables:                                                             */
/********************************************************************************/
COM_BASE         = 0x3F8 # See further down for valid I/O values
PANIC_KEY        = ' '  # Key to press to enter panic mode (default: <SPACE>)
PANIC_COUNT      = 5    # Number of times the key must be read to access panic mode
VMWARE_SUPPORT   = 1	# Include support for VMware platform. 
			# This is considered safe to keep, even if you don't use 
			# VMware, and may also lead to the console being accessible
			# even if Super I/O detection failed, if your chip resets
			# with COM1 enabled.
PERFORM_MSR_TEST = 0	# Set to nonzero if you want to have MSR test performed as
			# part of the 16550 UART checks. 
			# If you use VMware and direct serial to a file, you
			# should disable this test.
FORCE_PANIC      = 0	# Force panic mode on the first valid UART found without
			# waiting for panic key (for testing only)
MAX_LDN          = 0x20	# Maximum number of LDNs we test for UART functionality
USE_IO_DELAY     = 1	# Add a few idle cycles between in/out operations in close
			# sequence. This significantly increases the payload size
			# but might be safer, as per various BIOS ROMs disassembly.
USE_DIAGNOSTIC   = 1	# Send POST codes to a BIOS diagnostics card
TEST_EXTRA_PORTS = 1	# Test additional Super I/O ports beside 0x2E & 0x4E

# If you want to bypass (some of) the autodetection, and know your Super I/O base
# as well as the LDN of the UART, you can provide them below:
#SUPERIO_BASE     = 0x2e	# Super I/O base address
#SUPERIO_UART_LDN = 3	# LDN of the UART to use
#SUPERIO_TYPE     = 2	# 0 = NS, 1 = SMSC, 2 = VIA/Winbond/Nuvoton/Fintek,
			# 3 = Intel, 4 = ITE

# AMD SBxx0 extra build options (TODO: conditional SB detection)
SB800_48MHZ_INIT = 0	# Set to 1 to force 48 MHz clock init of AMD SB8x0 SouthBridge
SB900_48MHZ_INIT = 0	# Set to 1 to force 48 MHz clock init of AMD SB9x0 SouthBridge
			# NOTE: ONLY USE THE ABOVE IF YOU KNOW WHAT YOU ARE DOING
SB800_MMIO_PAGE  = 0x8000	# Page to map SB8x0/SB9x0 MMIO 


/********************************************************************************/
/* Constants:                                                                   */
/********************************************************************************/
# Super I/O PNP access generic constants
PNP_CC           = 0x02	# Configure Control
PNP_LDN          = 0x07	# Logical Device Number (LDN) register
PNP_ID           = 0x20	# Chip ID
PNP_POWER        = 0x22 # Subsytem power function
PNP_ACTIVATE     = 0x30	# Activate Register
PNP_IOBASE_HI    = 0x60	# I/O Port Base Address (MSB)
PNP_IOBASE_LO    = 0x61	# I/O Port Base Address (LSB)
# The VMware platform uses an emulated NS PC97338 as Super I/O
PC97338_FER      = 0x00	# Function Enable Register
PC97338_FAR      = 0x01	# Function Address Register
# CMOS RTC (used for timer functionality)
RTC_ADDRESS      = 0x70
# 16650 UART registers
COM_RBR          = 0x00	# Receive Buffer Register (ro)
COM_THR          = 0x00	# Transmit Holding Register (wo)
COM_DLL          = 0x00	# Baud Rate Divisor LSB (if DLAB is set)
COM_DLM          = 0x01	# Baud Rate Divisor MSB (if DLAB is set)
COM_IER          = 0x01	# Interrupt Enable Register
COM_IIR          = 0x02	# Interrupt Identification Register
COM_FCR          = 0x02	# 16650 FIFO Control Register (wo)
COM_LCR          = 0x03	# Line Control Register
COM_MCR          = 0x04	# Modem Control Registrer
COM_LSR          = 0x05	# Line Status Register
COM_SCR          = 0x07	# Scratch register
# PCI
PCI_ADDR         = 0xCF8
PCI_DATA         = 0xCFC
# AMD SBxx0 PM Register
AMD_SB_PM_ADDR   = 0xCD6
AMD_SB_PM_DATA   = 0xCD7
# According to the serial base, we need to set the I/O Range configuration differently
# See the various datasheets for reference
.if COM_BASE == 0x3F8
	AMD_SB_IO = 0x00000040
	INTEL_SB_IO = 0x30010010	# 0x3001 as MSW enables 0x2E & 0x4E + COMA I/O ranges
	# VM_SB_IO is not needed here
.elseif COM_BASE == 0x2F8
	AMD_SB_IO = 0x00000080
	INTEL_SB_IO = 0x30010001
	VM_SB_IO = 0x04
.elseif COM_BASE == 0x220
	AMD_SB_IO = 0x00000100
	INTEL_SB_IO = 0x30010002
	VM_SB_IO = 0xc8
.elseif COM_BASE == 0x228
	AMD_SB_IO = 0x00000200
	INTEL_SB_IO = 0x30010003
	VM_SB_IO = 0xcc
.elseif COM_BASE == 0x238
	AMD_SB_IO = 0x00000400
	INTEL_SB_IO = 0x30010004
	VM_SB_IO = 0x4c
.elseif COM_BASE == 0x2E8
	AMD_SB_IO = 0x00000800
	INTEL_SB_IO = 0x30010005
	VM_SB_IO = 0x0c
.elseif COM_BASE == 0x338
	AMD_SB_IO = 0x00001000
	INTEL_SB_IO = 0x30010006
	VM_SB_IO = 0x48
.elseif COM_BASE == 0x3E8
	AMD_SB_IO = 0x00002000
	INTEL_SB_IO = 0x30010007
	VM_SB_IO = 0x08
.else
  .print "Invalid COM_BASE"
  .abort
.endif


/********************************************************************************/


/********************************************************************************/
/* Macros:                                                                      */
/********************************************************************************/

# Jump to a subroutine
.macro  ROM_CALL addr
	mov  sp, offset 9f	# Use a local label as we don't know the size
	jmp  \addr		# of the jmp instruction (can be 2 or 3 bytes)
9:	# see http://sourceware.org/binutils/docs-2.21/as/Symbol-Names.html
.endm

# Fixes a binutil/ld bug where the address if off by 2 on cross section jumps
.macro  JMP_XS addr
.if JMP_WORKAROUND
	jmp  \addr + 2
.else
	jmp  \addr
.endif
.endm

# Read current super I/O base from data section (global pointer in MM0)
.macro  GET_SUPERIO_BASE
.ifdef SUPERIO_BASE
	mov  dx, SUPERIO_BASE
.else
	movd edi, mm0
	mov  dx, [di]
.endif
.endm

# Issue a POST code to an optional diagnostic card. Modifies AL.
.macro DIAG value
.if USE_DIAGNOSTIC
  .ifnes "\value", "al"
	mov  al, \value
  .endif
	out  0x80, al
.endif
.endm

# Add a 6 CPU cycles delay
.macro IO_DELAY
.if USE_IO_DELAY
	jmp  9f
9:	jmp  9f			# Label '9' is not used in the program
9:
.endif
.endm

# PCI helpers
.macro PCI_CONF_ADDROUT bus, device, function, address
.if \address & 0x03
.print "PCI config address must be 32 bit aligned"
.abort
.endif
	mov eax, 0x80000000 | (\bus << 24) | (\device << 11) | (\function << 8) | \address
	mov dx, PCI_ADDR
	out dx, eax
.endm
.macro PCI_CONF_IN32 bus, device, function, address
	PCI_CONF_ADDROUT \bus, \device, \function, \address
	mov dx, PCI_DATA
	in  eax, dx
.endm
.macro PCI_CONF_OUT32 bus, device, function, address, data
	PCI_CONF_ADDROUT \bus, \device, \function, \address
	mov dx, PCI_DATA
  .ifnes "\value", "eax"
	mov eax, \data
  .endif
	out dx, eax
.endm

# If using the calls below from a subroutine, remember to stack SP

# Write 'data' to to the PnP Super I/O register 'reg_index'
.macro  PNP_OUT reg_index, data
.ifeqs "\reg_index", "ah"
.print "Cannot use AH as register index in macro PNP_OUT"
.abort
.endif
.ifnes "\reg_index", "al"
	mov  al, \reg_index
.endif
.ifnes "\data", "ah"
	mov  ah, \data
.endif
	ROM_CALL superio_out
.endm

# Read data from the PnP Super I/O register 'reg_index'
.macro  PNP_IN reg_index
.ifnes "\reg_index", "al"
	mov  al, \reg_index
.endif
	ROM_CALL superio_in
.endm


/********************************************************************************/
/* begin : Dummy section marking the very start of the BIOS.                    */
/* This allows the .rom binary to be filled to the right size with objcopy.     */
/********************************************************************************/
.section begin, "a"			# The 'ALLOC' flag is needed for objcopy
	.ascii "UBRX v0.2"
	.align 16, 0xff
/********************************************************************************/


/********************************************************************************/
/* main:                                                                        */
/* This section is relocated according to the ld script.                        */
/********************************************************************************/
# TODO (if reports of inactive UART LDs): PnP register 22 & power on function

.section main, "ax"
.globl init			# init must be declared global for the linker
init:
	cli			# NOTE: we run with all interrupts disabled!
	cld			# String direction lookup: forward
	mov  ax, cs
	mov  ds, ax
	mov  ss, ax

	DIAG 0x10

	# Check MMX support (Intel Pentium MMX or later, AMD K6 or later)
	xor  edx, edx
	xor  eax, eax
	inc  eax		# Function #1 (Intel)
	cpuid
	shr  edx, 0x10
	and  dl, 0x80		# bit EDX:23
	jne  0f			# Intel MMX detected
	# Try AMD
	xor  edx, edx
	mov  eax, 0x80000001	# Function #1 (AMD)
	cpuid
	shr  edx, 0x10
	and  dl, 0x40		# bit EDX:22
	je   halt		# No MMX, no dice!

	DIAG 0x20

0:	ROM_CALL init_timer
	# The ISA PnP specs indicate to wait at least 2 ms before accessing a PnP device
	mov  cx, 5		# better conservative than sorry...
	ROM_CALL wait_timer

	DIAG 0x30
	
	# Access to LPC bus may need to be enabled after reset.
	ROM_CALL lpc_init
	
	# The Super I/O bases we probe (0x2E, 0x4E, 0x370, 0x3F0) are deemed safe as any
	# post '95 Super I/O is expected to start in PnP mode rather than legacy, and we
	# are not currently aware of any motherboard using a chip likely to create a
	# conflict at these I/O bases. For good measure, we also apply 2 extra checks.
	mov  di, offset pnp_superio_base 
	movd mm0, edi		# keep a pointer to superio base as global

check_pnp_base:
	GET_SUPERIO_BASE
	in   al, dx		# some Super I/Os need to be read after init,
	PUSHX al		# keep a copy of the original value of [base]
	in   al, dx
	# Enter conf mode
.ifdef SUPERIO_TYPE
	mov  cl, SUPERIO_TYPE
.else
	xor  cl, cl
.endif

enter_pnp_conf:
	GET_SUPERIO_BASE	# we're only writing to base here
	cmp  cl, 0x00		# National Semiconductor
	je   read_id		# no key required
	cmp  cl, 0x01		# SMSC
	jne  0f
	mov  al, 0x55		# key = 0x55
	jmp  1f
0:	cmp  cl, 0x02		# VIA/Winbond/Nuvoton/Fintek
	jne  0f
	mov  al, 0x87		# key = 0x87, 0x87
	out  dx, al
	IO_DELAY
	jmp  1f
0:	cmp  cl, 0x03		# Intel
	jne  0f
	mov  al, 0x80		# key = 0x80, 0x86
	out  dx, al
	IO_DELAY
	mov  al, 0x86
	jmp  1f
0:	mov  al, 0x87		# ITE
	out  dx, al
	IO_DELAY
	mov  al, 0x01
	out  dx, al
	IO_DELAY
	mov  al, 0x55
	out  dx, al
	cmp  dx, 0x2e
	je   1f			# key = 0x87, 0x01, 0x55, 0x55 if port 0x2E
	mov  al, 0xaa		# key = 0x87, 0x01, 0x55, 0xaa otherwise
1:	out  dx, al
	IO_DELAY

read_id:
	DIAG 0xF1
	xor  ah, ah		# clear panic result
	mov  al, PNP_ID		# attempt to read PnP Super I/O chip ID
	out  dx, al
	IO_DELAY
	inc  dx
	in   al, dx		# read the value at [base+1]
	cmp  al, 0xff		# we consider FF or 00 to mean not a PnP chip
	je   exit_pnp_conf	# perform an exit conf just in case
	cmp  al, 0x00
	je   exit_pnp_conf
	PUSHX al		# keep a copy of the original value of [base+1]

	# Extra safety test #1: try to change the id at [base+1] - it should not work
	mov  bl, al
	DIAG 0xF2
	mov  al, bl
	xor  al, 0x02		# flip only one of the lower bits
	out  dx, al
	IO_DELAY
	in   al, dx
	cmp  al, bl
	jne  restore_base_1	# the value has changed => not a PnP Super I/O

	# Extra safety test #2: Set LDN numbers and confirm that at least 2 of them stick
	DIAG 0xF3
	dec  dx
	mov  al, PNP_LDN
	out  dx, al
	inc  dx
	mov  bx, 0x01		# LDN index (start at 1 to avoid the 0 special case) 

test_ldn:
	mov  al, bl
	out  dx, al
	IO_DELAY
	in   al, dx
	cmp  al, bl
	jne  0f
	inc  ah
0:	inc  bl
	cmp  bl, 0x08		# 8 instead of MAX_LDN, to have at most 3 bits modified
	jl   test_ldn
	cmp  ah, 0x02
	jl   restore_base_1	# if less than 2 LDNs stuck, it's unlikely to be a PnP Super I/O

	# Passed the 2 extra safety test => proceed with full Super I/O and panic test
	PUSHX cl
	dec  dx
	ROM_CALL xt_init	# Some PnP chips require extra init
	ROM_CALL check_pnp_superio
	POPX cl
	mov  ah, al		# keep a copy of our return value in AH

restore_base_1:
	GET_SUPERIO_BASE
	mov  al, PNP_LDN	# in case this is a PnP chip, set the address to LDN before 
	out  dx, al		# we write at base+1, as writing an LDN is a safe operation
	IO_DELAY		# because of POPX
	inc  dx
	POPXP al		# original value of [base+1]
	out  dx, al

exit_pnp_conf:
	GET_SUPERIO_BASE
	cmp  cl, 0x00		# National Semiconductor
	je   2f			# no exit sequence
	cmp  cl, 0x02		# SMSC + VIA/Winbond/Nuvoton/Fintek
	jg   0f
	mov  al, 0xaa		# exit key = 0xaa
	jmp  1f
0:	cmp  cl, 0x03		# Intel
	jne  0f
	mov  al, 0x68		# exit key = 0x68, 0x08
	out  dx, al
	mov  al, 0x08
	jmp  1f
0:	mov  al, PNP_CC		# ITE
	out  dx, al
	inc  dx
	mov  al, 0x02	 	# ISA PnP: return to Wait for Key
1:	out  dx, al
2:	inc  cl
	or   ah, ah
	jne  0f			# cut short if panic mode was successfull
.ifndef SUPERIO_TYPE
	cmp  cl, 0x04
	jl   enter_pnp_conf	# try next config key with same base
.endif

0:	dec  dx			# base
	POPXP al		# original value of [base]
	# We waited on the stack to exit to panic mode
	or   ah, ah		# check last panic mode return value
	jne  enter_panic	# success
	out  dx, al		# restore the original value at [base]

.ifndef SUPERIO_BASE
	movd edi, mm0		# try next Super I/O base
	add  di, 0x02
	movd mm0, edi		# keep the updated copy
	cmp  di, offset pnp_superio_base_end
	jne  check_pnp_base	# try next base
.endif
	
	# No success from PNP Super I/O check => fallback to VMware (or exit)
.if VMWARE_SUPPORT
	# The VMware super I/O is a virtual NS PC97338 (in NON PnP mode) at 0x2E:
	# http://www.datasheetcatalog.org/datasheet/nationalsemiconductor/PC97338.pdf
	# NB: VM's PC97338 deviates from NS as SCC1 is not in Test Mode on reset.
	
	# In case we're not running on VMware and ports 2E/2F actually map to
	# a physical chip that follows the ISA PnP specs, writing to VM's FER
	# register (address 0) could potentially change the default address for 
	# the PnP data read port as per the ISA PnP specs.
	# The trick, since the bit we want set will also be set if we "switch" 
	# the default ISA PnP readout address to 0x2F, is to just use that value.
	# Thus, we write 0x0B (= 0x2F >> 2) instead of just the 0x02 we need.
	mov  dx, 0x2e		# VMware Super I/O base
	in   al, dx		# keep a copy of the original value at 0x2E
	mov  bl, al
	mov  al, PC97338_FER	# FER register (address 0)
	out  dx, al
	IO_DELAY
	inc  dx
	in   al, dx		# keep a copy of the original value at 0x2F
	mov  bh, al
	mov  al, 0x0b		# Enable SCC1, PP and FDC (see above)
	out  dx, al
	# That's all that's actually needed when using 0x3F8 as base
	# (previous probing of 0x2E for PnP Super I/O doesn't interfere)
.if COM_BASE != 0x3F8		# No need for extra init for default serial base
	dec  dx
	mov  al, PC97338_FAR
	out  dx, al
	inc  dx
	mov  al, VM_SB_IO
	out  dx, al
.endif
	shl  ebx, 0x10		# next call modifies BX (but not MSW of EBX)
	ROM_CALL check_16550	# check for (emulated) 16550
	or   al, al
	jne  vm_restore
	ROM_CALL init_serial	# 115200 8N1 no handshake
.if FORCE_PANIC
	mov  al, 0x01
.else
	ROM_CALL check_panic	# returns nonzero on success
.endif
	or   al, al
	jne  enter_panic
vm_restore:	
	shr  ebx, 0x10
	mov  dx, 0x2e		# VMware Super I/O base
	mov  al, bl
	out  dx, al		# Restore original values before we leave
	IO_DELAY
	inc  dx
	mov  al, bh
	out  dx, al
.endif
	jmp  halt		# If compiled without VMware support

enter_panic:
	DIAG 0x80
	JMP_XS enter_console

# TODO: proceed to booting normal BIOS
halt:
0:	hlt
	jmp  0b


/********************************************************************************/
/* Subroutines:                                                                 */
/********************************************************************************/

# MODIFIES EAX, DX
# Init LPC access for chipset that require it (Intel ICH#, AMD SB6x0-SB9x0)
# IN: none
# OUT: none
lpc_init:
	# Operate on 32 bit as PCI Configuration space is 32 bit aligned
	PCI_CONF_IN32 0, 0x1e, 0, 0x00	# ICH DMI to PCI bridge (bus 0, device 30, function 0)
	cmp  eax, 0x244e8086		# Intel ICH# (desktop)
	je   lpc_intel
	cmp  eax, 0x24488086		# Intel ICH-M# (mobile)
	je   lpc_intel
	PCI_CONF_IN32 0, 0x14, 3, 0x00	# AMD SBxx0 SouthBridge (bus 0, device 20, function 3)
	cmp  eax, 0x439d1002		# SB7x0, SB9x0(?)
	je   lpc_amd
	cmp  eax, 0x438d1002		# SB6x0, SB8x0
	je   lpc_amd
	jmp  sp
lpc_amd:
	PCI_CONF_OUT32 0, 0x14, 3, 0x44, AMD_SB_IO
	PCI_CONF_OUT32 0, 0x14, 3, 0x48, 0x0000ff03	# 0x2E/0x4E forwarding, everything else disabled

.if SB800_48MHZ_INIT | SB900_48MHZ_INIT	# Force 48 MHz clock init (/!\ DOES NOT CHECK FOR VALID SB)
	# We have the choice of switching to 32 bit, to use the MMIO default base of 0xFED80000
	# or change this base to a 20 bit address (real-mode). We choose the latter
	mov  dx, AMD_SB_PM_ADDR
	mov  al, 0x27			# AcpiMmioEn (MSB)
	out  dx, al
	inc  dx
# DEBUG
	DIAG 0xFE
	in   al, dx
	cmp  al, 0xfe			# Confirm that our MMIO mapping works
	jne  halt
# END_DEBUG
	xor  al, al			# Set AcpiMMioAddr to something we can access in real mode
	out  dx, al
	dec  dx
	mov  al, 0x26
	out  dx, al
	inc  dx
	mov  al, SB800_MMIO_PAGE >> 12
	out  dx, al
	dec  dx
	mov  al, 0x25
	out  dx, al
	inc  dx
	in   al, dx
	and  al, 0x0f
	or   al, (SB800_MMIO_PAGE >> 4) & 0xf0
	out  dx, al
	dec  dx
	mov  al, 0x24			# AcpiMmioEn (LSB)
	out  dx, al
	inc  dx
	in   al, dx
	or   al,  (1 << 0)		# enable AcpiMMio space
	and  al, ~(1 << 1)		# disable I/O-mapped space, use Memory-mapped instead
	out  dx, al
	
	mov  ax, SB800_MMIO_PAGE	# Set our base page
	mov  es, ax			# ES does not need to be restored
	mov  di, 0xe00 + 0x40		# Misc. Registers: MiscClkCntrl
	mov  al, [di]
	and  al, 0xf8
	or   al, 0x02			# Enable and set Device_CLK1 (Super I/O) to 48 Mhz
	mov  [di], al
# TODO: SB900 vs SB800 detection
.if SB900_48MHZ_INIT
 	# Program ClkDrvSth2 OSCOUT1_CLK_sel for 48 MHz (default is 14 MHz)
	mov  di, 0xe00 + 0x28
	mov  eax, [di]
	and  eax, ~(7 << 16)
	or   eax,  (2 << 16)
	mov  [di], eax
.endif
.endif
	jmp  sp
lpc_intel:
	# LPC is device 31, function 0
	PCI_CONF_OUT32 0, 0x1f, 0, 0x80, INTEL_SB_IO
	jmp  sp

# MODIFIES: DX, AX, EDI
# Write data to PnP Super I/O
# IN: AL = Register index, AH = Data byte to Write
# OUT: none
superio_out:
	GET_SUPERIO_BASE
	out  dx, al
	IO_DELAY
	inc  dx
	xchg al, ah
	out  dx, al
	IO_DELAY
	jmp  sp

# MODIFIES: DX, AL, EDI
# Read data from PnP Super I/O
# IN: AL = Register index
# OUT: AL = Data byte Read
superio_in:
	GET_SUPERIO_BASE 
	out  dx, al
	IO_DELAY
	inc  dx
	in   al, dx
	IO_DELAY
	jmp  sp

# MODIFIES: DX, AX
# Write data to serial register
# IN: AL = COM Register index, AH = Data byte to Write
# OUT: none
serial_out:
	mov  dx, COM_BASE
	add  dl, al		# We don't overflow to DH
	mov  al, ah
	out  dx, al
	IO_DELAY
	jmp  sp

# MODIFIES: DX, SI, CX, AX
# Init serial port
# IN: none
# OUT: none
init_serial:
	PUSH_SP
	mov  si, offset serial_conf
	mov  cx, (serial_conf_end - serial_conf)/2
write_serial_conf:
	mov  ax, [si]
	ROM_CALL serial_out
	add  si, 0x02
	loop write_serial_conf
	# empty FIFO if needed
0:	mov  dx, COM_BASE + COM_LSR
	in   al, dx
	IO_DELAY
	and  al, 0x01
	je   0f
	mov  dx, COM_BASE
	in   al, dx
	IO_DELAY
	jmp  0b
0:	POP_SP
	jmp  sp

# MODIFIES: DX, AX
# Print a character to serial output
# IN: AL = character to output
# OUT: none
.globl putchar
putchar:
	mov  dx, COM_BASE + COM_LSR
	mov  ah, al
tx_wait:
	in   al, dx
	IO_DELAY
	and  al, 0x20		# Check that transmit buffer is empty
	jz   tx_wait
	mov  dx, COM_BASE + COM_THR
	mov  al, ah
	out  dx, al
	jmp  sp

# MODIFIES: AX, CX, DX
# Read a serial char with timeout. Wait indefinitely if timeout = 0.
# IN: CX = timeout in ~1 ms (+/- ~1 ms => MUST be at least 2)
# OUT: AX = character read from serial, or 0xFFFF if timeout
.globl readchar
readchar:
	xor  ax, ax
	mov  dx, RTC_ADDRESS
	mov  al, 0x0C		# clear any existing PI by reading register C
	out  dx, al
	IO_DELAY
	inc  dx
	in   al, dx
	IO_DELAY

0:	mov  dx, COM_BASE + COM_LSR
	in   al, dx
	IO_DELAY
	and  al, 0x01
	jne  0f			# got a character
	or   cx, cx		# if timeout is zero, wait forever
	je   0b
	mov  dx, RTC_ADDRESS
	mov  al, 0x0C		# check for PI
	out  dx, al
	IO_DELAY
	inc  dx
	in   al, dx
	and  al, 0x40
	je   0b			# PI bit is only set once per ms
	loop 0b			# PI bit was set => decrement 1 ms from timeout

	mov  ax, 0xffff		# no character was read => return -1
	jmp  sp
0:	mov  dx, COM_BASE + COM_RBR
	in   al, dx		# return character
	IO_DELAY
	jmp  sp

# MODIFIES: AL, DX
# Initialize a ~1 millisecond timer using the RTC SQW generator
# We prefer using RTC over the PIC as it is more convenient for our purpose.
# We set a Periodic Interrupt clock of 1024 Hz, which we poll
# IN: none
# OUT: none
init_timer:
	mov  dx, RTC_ADDRESS
	mov  al, 0x0A		# RTC Status Register A
	out  dx, al
	IO_DELAY
	inc  dx
	in   al, dx
	IO_DELAY
	and  al, 0xf0		# Set Periodic Interrupt frequency
	or   al, 0x06		# 1024 Hz
	out  dx, al
	IO_DELAY
	dec  dx

	mov  al, 0x0B		# RTC Status Register A
	out  dx, al
	IO_DELAY
	inc  dx
	in   al, dx
	IO_DELAY
	or   al, 0x40		# Enable Periodic Interrupt
	out  dx, al
	jmp  sp

# MODIFIES: AL, CX, DX
# Wait for a specific duration in ~1ms units
# IN: CX = timeout in ~1 ms (+/- ~1 ms => MUST be at least 2)
# OUT: none
wait_timer:
	mov  dx, RTC_ADDRESS
	mov  al, 0x0C
	out  dx, al
	IO_DELAY
	inc  dx
	in   al, dx		# clear any existing PI by reading register C
	IO_DELAY
0:	in   al, dx
	IO_DELAY
	and  al, 0x40
	je   0b			# PI bit is only set once per ms
	loop 0b			# PI bit was set => decrement 1 ms from timeout
	jmp  sp

# MODIFIES: DX, AX
# Print a NUL terminated string to serial
# IN: SI = offset to NUL terminated string
.globl print_string
print_string:
	PUSH_SP
next_char:
	lodsb
	or   al, al
	je   ps_exit
	ROM_CALL putchar
	jmp  next_char
ps_exit:
	POP_SP
	jmp  sp

# MODIFIES: EBX, CX, DX
# Print an hex longword to serial
# IN: EAX = longword to print in hex
# OUT: none
.globl print_hex
print_hex:
	PUSH_SP
	mov  ebx, eax
	mov  al, ' '
	ROM_CALL putchar
	mov  al, '$'
	ROM_CALL putchar
	mov  cx, 8
one_digit:
	rol  ebx, 4
	mov  al, bl
	and  al, 0x0f
	cmp  al, 0x0a
	jl   alpha
	add  al, 'A' - '0' - 0x0a
alpha:
	add  al, '0'
	ROM_CALL putchar
	loop one_digit
	mov  al, '\r'
	ROM_CALL putchar
	mov  al, '\n'
	ROM_CALL putchar
	mov  eax, ebx
	POP_SP
	jmp  sp

# MODIFIES: AX, EBX, CX, DX, SI
# Peforms extra initialization for PnP Super I/Os that require it
# IN: DX = Super I/O base
# OUT: none
xt_init:
	DIAG 0x76
	mov  al, PNP_ID
	out  dx, al
	IO_DELAY
	inc  dx
	in   al, dx
	shl  ax, 0x08
	dec  dx
	mov  al, PNP_ID+1
	out  dx, al
	IO_DELAY
	inc  dx
	in   al, dx
	mov  cx, ax		# CX  = 2 byte chip ID
	mov  si, offset special_init
xti_chip:
	mov  ebx, [si]		# read both the mask and ID at once
	add  si, 4
	mov  ax, cx
	and  ax, bx		# apply mask
	shr  ebx, 0x10
	cmp  ax, bx		# compare with ID
	je   xti_match
0:	add  si, 3		# skip data section
	mov  al, [si]
	cmp  al, 0xff		# end of section marker
	jne  0b
	inc  si
	cmp  si, offset special_init_end
	jne  xti_chip
	jmp  sp
xti_match:
	DIAG 0x77
	mov  al, [si]
	dec  dx
	out  dx, al
	inc  dx
	inc  si
	mov  ah, [si]
	inc  si
	in   al, dx
	and  al, ah
	mov  ah, [si]
	inc  si
	or   al, ah
	out  dx, al
	mov  al, [si]
	cmp  al, 0xff
	jne  xti_match
	jmp  sp

# MODIFIES: EAX, EBX, ECX, EDX
# Check whether a PnP SuperI/O with a 16550 Logical Device resides at the current base
# IN: none
# OUT: nonzero AL if an LD qualified for panic mode, zero otherwise
check_pnp_superio:
	PUSH_SP			# We're going to call more subroutines
	# Disable ALL Logical Devices (main BIOS will reenable them as needed)
	xor  bl, bl		# BL = Logical Device Number
deactivate_ldn:
	PNP_OUT PNP_LDN, bl
	PNP_OUT PNP_ACTIVATE, 0x00	# isolate from the ISA bus
	inc  bl
	cmp  bl, MAX_LDN
	jl   deactivate_ldn

	# At this stage, all LDs are isolated from the ISA bus
.ifdef SUPERIO_UART_LDN
	mov  bl, SUPERIO_UART_LDN
.else
	xor  bl, bl		# BL = Logical Device Number
.endif
check_ldn:
	PNP_OUT PNP_LDN, bl
	# Keep a copy of original I/O Base
	PNP_IN PNP_IOBASE_HI
	shl  ax, 0x08
	PNP_IN PNP_IOBASE_LO
	mov  dx, ax
	PUSHX dx		# keep a copy of I/O base
	# Set our own base (any possible conflict has been isolated)
	PNP_OUT PNP_IOBASE_HI, COM_BASE >> 8
	PNP_OUT PNP_IOBASE_LO, COM_BASE & 0xff
	PNP_OUT PNP_ACTIVATE, 0x01	# only LD on our bus
	PUSHX bl		# keep a copy of BL (next call modifies BX)
	ROM_CALL check_16550	# check if LD is a 16550
	POPX bl
	DIAG al
	or   al, al
	jne  next_ldn
	ROM_CALL init_serial
.if FORCE_PANIC
	mov  al, 0x01
.else
	ROM_CALL check_panic	# returns nonzero on success
.endif
	or   al, al
	jne  cps_exit
next_ldn:			# Didn't qualify => disable and restore base
	POPX cx			# I/O base copy
	PNP_OUT PNP_ACTIVATE, 0x00
	PNP_OUT PNP_IOBASE_HI, ch
	PNP_OUT PNP_IOBASE_LO, cl
.ifndef SUPERIO_UART_LDN
	inc  bl
	cmp  bl, MAX_LDN
	jl   check_ldn		# next LDN to test
.endif
	xor  al, al		# exhausted all LDNs without success
cps_exit:
	POP_SP
	jmp  sp	

# MODIFIES EAX, BX, ECX, DX
# _Safely_ finds out whether a Logical Device is an 16550 UART
# IN: none
# OUT: zero in AL if the LD is a 16550, or the nonzero index of the failed test
check_16550:
	PUSH_SP			# We may call putchar
	# 1. Check 16650 default register values on reset (read-only test),
	# as per http://www.national.com/ds/PC/PC16550D.pdf
	# Even if we are receiving data, 16550 compliant registers will be
	# in a well known state on reset
	mov  bl, 0x01		# error code
	mov  dx, COM_BASE + COM_IER
	in   al, dx		# IER
	cmp  al, 0x00		# IER is 0 on reset as per the datasheet. A 16550 compliant chip
	jne  c16550_exit	# always leaves interrupts disabled on reset
	inc  bl	# 0x02
	inc  dx
	in   al, dx		# IIR
	cmp  al, 0x01		# No interrupt pending (bit 1) and everything else is zero since
	jne  c16550_exit	# interrupts are disabled. A standard 16550 implementation also
	inc  bl	# 0x03		# disables both FIFOs on reset.
	inc  dx
	in   al, dx		# LCR
	and  al, 0xfc		# Expected zero, but some nonstandard 16550 implementations
	jne  c16550_exit	# have length set to 8 instead of 5 at reset => mask lower bits
				# other bits such as number of stop bits, parity, break and DLAB
	inc  bl	# 0x04		# will be set to zero on reset, in a 16550 compliant implementation
	inc  dx
	in   al, dx		# MCR
	cmp  al, 0x00		# We're not driving anything out and a 16550 compliant chip should
	jne  c16550_exit	# not reset with loop set, so zero is expected
	inc  bl	# 0x05
	inc  dx
	in   al, dx		# LSR
	and  al, 0xf4		# We may be receiving data, hence:
				# 0: data available   = possible
				# 1: overrun error    = possible
				# 2: parity error     = not possible (as parity is not set)
				# 3: framing error    = possible
				# 4: break interrupt  = not possible, unless the other end set their
				#    baudrate very low. In the case of a panic-room implementation
				#    at 115200 bauds, we will never get spacing logic long enough
				#    to cause a break interrupt
				# 5 THR empty         = always true
				# 6 THR and TSR empty = always true
				# 7 Error in RVC FIFO = not possible (FIFO not enabled)	
	cmp  al, 0x60
	jne  c16550_exit
	inc  bl	# 0x06
	# The MSR test is a biy tricky. On real hardware, MSR should be zero, as all
	# forms of hardware handshaking are requested to be disabled for failsafe
	# console operations. In a virtual 16550 implementation however, the hardware
	# lines may be simulated active for VM apps so we may not get zero (in effect
	# we get 0xBB on VMware when directing serial output to a file).
	# Only perform this test is explicitly requested.
	inc  dx
.if PERFORM_MSR_TEST
	in   al, dx		# MSR
	cmp  al, 0x00		# should be zero unless hardware handshake is in use
	jne  c16550_exit
.endif
	inc  bl	# 0x07

	# 2. Check 16550 scratch register access by flipping a single bit
	#    The reason we try a bit flip on the scratch register is because
	#    it is the farthest register down the I/O address range (7), hence
	#    safe for any Logical Device that offers less than 8 ports, and we
	#    use bit 6 as this is statistically the least likely to cause harm
	#    (unimplemented/reserved bits are usually MSb ones, but don't go
	#    for 7, as it is often used as mask toggle)
	inc  dx			# SCR
	in   al, dx
	mov  ah, al
	xor  al, 0x40		# flip bit 6
	xor  ah, al		# what we expect to read back (bit isolated)
	out  dx, al
	IO_DELAY	
	in   al, dx		# readback
	and  al, 0x40		# isolate the bit
	cmp  ah, al
	jne  c16550_exit	# bit still in original position => not a 16550
	inc  bl	# 0x08
	xor  al, 0x40
	out  dx, al		# safely restore bit (don't leave it on longer than needed)
	IO_DELAY	
	mov  ah, al
	in   al, dx		# extra sanity check
	cmp  al, ah
	jne  c16550_exit	# our bit restore failed => not a 16550
	inc  bl	# 0x09
	
	# 3. Check one of the unflippable bits from IER
	mov  dx, COM_BASE + COM_IER
	in   al, dx
	or   al, al		# sanity check, should still be 0
	jne  c16550_exit
	inc  bl	# 0x0a
	mov  al, 0x40		# As per the 16550D specs "bits 4 to 7 are always logic 0"
	out  dx, al
	IO_DELAY
	in   al, dx
	or   al, al
	je   0f			# should still be zero
	xor  al, al		# nonzero => restore "IER" before we leave
	out  dx, al
	jmp  c16550_exit
0:	inc  bl	# 0x0b
	
	# 4. Now set DLAB and flip the same bit (twice) - unlike previous test, it should stick
	mov  dx, COM_BASE + COM_LCR
	in   al, dx		# don't assume anything
	mov  ah, al		# original LCR in AH
	and  al, 0xfc
	jne  c16550_exit	# sanity check - should still be zero
	inc  bl	# 0x0c		# we just confirmed LCR to be 0000 00xx
	mov  al, ah
	or   al, 0x80		# Set DLAB
	out  dx, al
	shl  eax, 0x08		# keep a copy of original LCR in 3rd byte of EAX
	mov  dx, COM_BASE + COM_IER
	in   al, dx
	mov  cl, al		# "DLM" can be nonzero => keep a copy in CL
	xor  al, 0x40		# flip bit 6
	out  dx, al
	IO_DELAY
	in   al, dx
	xor  al, cl
	cmp  al, 0x40		# did it stick?
	je   0f
	inc  bl # 0x0d		# we'll check this errcode later
	# fallthrough, as we need to restore "IER/DLM" before we leave
0:	mov  al, cl		# unflip the bit (restore old value)
	out  dx, al
	IO_DELAY
	in   al, dx
	cmp  al, cl
	jne  restore_dlab	# NB: will return code 0x0c
	cmp  bl, 0x0d		# now we can check for previous error
	je   restore_dlab
	inc  bl
	inc  bl	# 0x0e
	
	# 5. We're pretty sure this is a a 16550, but to leave absolutely no doubt,
	#    set max baudrate, try a loop test and confirm we get good data.
	
	# 5a. Set max baudrate
	mov  dx, COM_BASE + COM_DLL
	# keep a copy of the original divisor in CX (CL = DLM, CH = DLL)
	in   al, dx
	mov  ah, al
	inc  dx
	in   al, dx
	mov  cx, ax	
	# write new divisor 0x0001	
	xor  al, al
	out  dx, al		# DLM = 0x00
	IO_DELAY
	in   al, dx		# sanity check
	or   al, al
	jne  restore_dlm
	inc  bl # 0x0f
	inc  al	
	dec  dx
	out  dx, al		# DLL = 0x01
	IO_DELAY
	in   al, dx		# sanity check
	cmp  al, 0x01
	jne  restore_dll
	inc  bl	# 0x10

	# 5b. unset DLAB so that we can access THR and RBR
	# NB: clearing DLAB usually has the side effect of outputting data
	shr  eax, 0x10          # copy of original LCR
	mov  dx, COM_BASE + COM_LCR
	out  dx, al
	IO_DELAY

	# 5c. Put 16550 in loop mode
	mov  dx, COM_BASE + COM_MCR
	in   al, dx
	cmp  al, 0x00		# more sanity - MCR should still be zero
	jne  restore_dll
	inc  bl	# 0x11
	mov  al, 0x10		# loop mode
	out  dx, al
	IO_DELAY
	in   al, dx
	cmp  al, 0x10
	jne  restore_dll	# sanity check
	inc  bl	# 0x12
	
	# 5d. write a byte, see if we read it back (NOTE: 5 bit length is to be assumed)
	mov  dx, COM_BASE + COM_THR
	in   al, dx
	IO_DELAY
	mov  ah, al		# keep a copy in case we need to restore
	mov  al, 0x15		# 5 bit test pattern (most 16550s start in 5 bits mode)
	out  dx, al

	shl  ecx, 0x10		# we'll need CX => preserve divisor backup
	mov  cx, 50
	ROM_CALL readchar
	and  al, 0x1f
	cmp  al, 0x15		# will also fail if timeout (AX = 0xffff)
	jne  restore_thr	# loop test failure
	xor  bl, bl		# report success
	jmp  unset_loop
	
restore_thr:
	mov  dx, COM_BASE + COM_THR
	mov  al, ah
	out  dx, al
	IO_DELAY
unset_loop:
	mov  dx, COM_BASE + COM_MCR
	in   al, dx
	IO_DELAY
	and  al, 0xef		# safely unset loop mode (register may not be zero)
	out  dx, al
	IO_DELAY
restore_dll:
	mov  dx, COM_BASE + COM_DLL
	mov  al, ch
	out  dx, al
	IO_DELAY
restore_dlm:
	mov  dx, COM_BASE + COM_DLM
	mov  al, cl
	out  dx, al
	IO_DELAY
restore_dlab:
	shr  eax, 0x10		# copy of original LCR
	mov  dx, COM_BASE + COM_LCR
	out  dx, al
c16550_exit:
	mov  al, bl
	POP_SP
	jmp  sp

# MODIFIES: AX, BL, CX, DX
# Reads serial port for panic mode key
# IN: none
# OUT: nonzero AL if panic mode was requested, zero otherwise
check_panic:
	PUSH_SP
	mov  al, '?'
	ROM_CALL putchar
	mov  bl, 0
0:	mov  cx, 50		# On VMware, it takes up to 50 ms
	ROM_CALL readchar	# for readchar to be ready
	cmp  al, PANIC_KEY
	je   1f
	xor  al, al
	jmp  cp_exit
1:	inc  bl
	cmp  bl, PANIC_COUNT
	jl   0b
	mov  al, 0x01
cp_exit:
	POP_SP
	jmp  sp


/********************************************************************************/
/* Data:                                                                        */
/********************************************************************************/
SETUP_STACK_DATA		# See mmx_stack.inc
pnp_superio_base:		# Base addresses we test for a Super I/O chip
	.word 0x2e, 0x4e
.if TEST_EXTRA_PORTS
	.word 0x370, 0x3f0
.endif
pnp_superio_base_end:
serial_conf:			# See http://www.versalogic.com/kb/KB.asp?KBID=1395
	.byte COM_MCR, 0x00	# RTS/DTS off, disable loopback
	.byte COM_LCR, 0x80	# Set DLAB (access baudrate registers)
	.byte COM_DLL, 0x01	# Baud Rate 115200 = 0x0001
	.byte COM_DLM, 0x00
	.byte COM_LCR, 0x03	# Unset DLAB. Set 8N1 mode
	.byte COM_FCR, 0x07	# Enable & reset FIFOs. DMA mode 0.
serial_conf_end:
# Extra configuration for PnP chip that require it
special_init:
	# WinBond W83977TF (testing)
#	.word 0xffff		# PnP chip ID mask
#	.word 0x9773		# PnP chip ID (big endian format: [0x20][0x21])
#	.byte 0x22		# PnP register index
#	.byte 0xfe		# AND mask to apply (clear bits - here, clear bit 0)
#	.byte 0x30		# OR value to apply (set bits - here, set bits 4&5)
#	.byte 0xff		# end of section
	# The Nuvoton NCT6776F defaults with Serial A & B disabled => enable them
	.word 0xffff
	.word 0xc333		# NCT6776F chip ID
	.byte 0x2a		# Multi Function Selection register
	.byte 0x1f		# bit 7, 6 & 5 cleared => Serial A & B enabled
	.byte 0x00
	.byte 0xff		# end of section
special_init_end:
/********************************************************************************/


/********************************************************************************/
/* reset: this section must reside at 0xfffffff0, and be exactly 16 bytes       */
/********************************************************************************/
.section reset, "ax"
	JMP_XS init		# When jumping between sections, ld is off by 2
	.align 16, 0xff		# fill section up to end of ROM (with 0xFF)
/********************************************************************************/
