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
/* Macros:                                                                      */
/********************************************************************************/

# Issue a POST code to an optional diagnostic card. Modifies AL.
.macro DIAG value
.if USE_DIAGNOSTIC
  .ifnes "\value", "al"
	mov  al, \value
  .endif
	out  0x80, al
.endif
.endm

# Fixes a binutil/ld bug where the address may be off by 2 on cross section jumps
.macro  JMP_XS addr
	jmp  \addr + JMP_WORKAROUND_OFFSET
.endm

# Jump to a subroutine (from same or different section)
.macro  ROM_CALL addr
	mov  sp, offset 9f	# Use a local label as we don't know the size
	jmp  \addr		# of the jmp instruction (can be 2 or 3 bytes)
9:	# see http://sourceware.org/binutils/docs-2.21/as/Symbol-Names.html
.endm
# Same as above, but using BP instead of SP for return address
.macro  ROM_CALL_BP addr
	mov  bp, offset 9f
	jmp  \addr
9:
.endm
# Same as the first, but potentially patches for cross-segment
.macro  ROM_CALL_XS addr
	mov  sp, offset 9f
	JMP_XS \addr
9:
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
