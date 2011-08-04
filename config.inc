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

/********************************************************************************/
/* Build variables:                                                             */
/********************************************************************************/
COM_BASE         = 0x3F8   # See further down for valid I/O values
BAUDRATE_DIVISOR = 0x0001  #  4800 = 0x0018,  9600 = 0x000C,  19200 = 0x0006,
                           # 38400 = 0x0003, 57600 = 0x0002, 115200 = 0x0001
                           # We default to 57600, as a higher baudrate can lead to
                           # FIFO overflow if the flash access is slow (eg. 150 ns)
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
