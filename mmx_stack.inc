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

# The following defines macros to allow the use of MMX as an elementary stack 
# For PUSHX, up to 8 bytes can be stacked. For PUSH_SP, up to 4 SPs (8 bytes).
# MM5 to MM7 are used (though MM7 is only used a scratch for pop/push)
# The macros expect lowercase registers. i.e. 'PUSHX ax' and not 'PUSHX AX'
# The macros are:
# PUSHX <reg>: pushes a byte, word or long register. Original content of
#   extended register, if it applies (eg. EAX if AX is pushed), is preserved.
# PUSH_SP: pushes SP (using a separate stack)
# POPX <reg>: pops a byte, word or long register. Original content of extended
#   register, if it applies, is DESTROYED
# POPXP <reg>: pops a byte, word or long register while preserving the original
#   content of the register. Note that this is more costly in size and also
#   requires the use of EBP as an additional scratch register (which content will
#   be destroyed)
# POP_SP: pops SP. The high word of ESP is DESTROYED during this operation


# Compute stack delta, in bytes, according to the register being used
.macro GET_GP_STACK_DELTA reg
GP_STACK_DELTA = 1
.ifeqs "\reg", "ax"
GP_STACK_DELTA = 2
.endif
.ifeqs "\reg", "bx"
GP_STACK_DELTA = 2
.endif
.ifeqs "\reg", "cx"
GP_STACK_DELTA = 2
.endif
.ifeqs "\reg", "dx"
GP_STACK_DELTA = 2
.endif
.ifeqs "\reg", "di"
GP_STACK_DELTA = 2
.endif
.ifeqs "\reg", "si"
GP_STACK_DELTA = 2
.endif
.ifeqs "\reg", "bp"
GP_STACK_DELTA = 2
.endif
.ifeqs "\reg", "sp"
GP_STACK_DELTA = 2
.endif
.ifeqs "\reg", "eax"
GP_STACK_DELTA = 4
.endif
.ifeqs "\reg", "ebx"
GP_STACK_DELTA = 4
.endif
.ifeqs "\reg", "ecx"
GP_STACK_DELTA = 4
.endif
.ifeqs "\reg", "edx"
GP_STACK_DELTA = 4
.endif
.ifeqs "\reg", "edi"
GP_STACK_DELTA = 4
.endif
.ifeqs "\reg", "esi"
GP_STACK_DELTA = 4
.endif
.ifeqs "\reg", "ebp"
GP_STACK_DELTA = 4
.endif
.ifeqs "\reg", "esp"
GP_STACK_DELTA = 4
.endif
.endm

# Find the associated extended register
.macro GET_EREG reg
.if GP_STACK_DELTA == 4
	EREG = \reg
.elseif GP_STACK_DELTA == 2
	EREG = e\reg
.else
.ifeqs "\reg", "al"
	EREG = eax
.endif
.ifeqs "\reg", "ah"
	EREG = eax
.endif
.ifeqs "\reg", "bl"
	EREG = ebx
.endif
.ifeqs "\reg", "bh"
	EREG = ebx
.endif
.ifeqs "\reg", "cl"
	EREG = ecx
.endif
.ifeqs "\reg", "ch"
	EREG = ecx
.endif
.ifeqs "\reg", "dl"
	EREG = edx
.endif
.ifeqs "\reg", "dh"
	EREG = edx
.endif
.endif
.endm

# When using AH, BH, CH, DH, swaping with low register byte is needed
.macro SWAP_IF_NEEDED reg
.ifeqs "\reg", "ah"
	xchg ah, al
.endif
.ifeqs "\reg", "bh"
	xchg bh, bl
.endif
.ifeqs "\reg", "ch"
	xchg ch, cl
.endif
.ifeqs "\reg", "dh"
	xchg dh, dl
.endif
.endm

# Push a long, word or byte register
.macro  PUSHX reg
GET_GP_STACK_DELTA \reg
GET_EREG \reg
SWAP_IF_NEEDED \reg
	movd  mm7, EREG
.if (GP_STACK_DELTA == 1)
	pand  mm7, [mmx_000000ff]
.elseif (GP_STACK_DELTA == 2)
	pand  mm7, [mmx_0000ffff]
.endif
	psllq mm5, (GP_STACK_DELTA * 0x08)
	por   mm5, mm7
SWAP_IF_NEEDED \reg
.endm

# Pop a long, word or byte register, with or without preserving original extended register
.macro  POPX_COMMON reg, preserve
GET_GP_STACK_DELTA \reg
.if (GP_STACK_DELTA <= 2) && (\preserve != 0)
	xor \reg, \reg		# Must be zero as we'll OR it
.endif
GET_EREG \reg
.if (\preserve != 0)
SWAP_IF_NEEDED \reg
.endif
.if (GP_STACK_DELTA == 4) || (\preserve == 0)
	movd  EREG, mm5
.elseif (\preserve != 0)
	movq  mm7, mm5
  .if GP_STACK_DELTA == 2
	pand  mm7, [mmx_0000ffff]
  .else
	pand  mm7, [mmx_000000ff]
  .endif
	movd  ebp, mm7		# We must use an extra register here
  .ifeqs "\reg", "bp"
  .print "Cannot POP BP"
  .abort
  .endif
	or    EREG, ebp
.endif
	psrlq mm5, (GP_STACK_DELTA * 0x08)
SWAP_IF_NEEDED \reg
.endm

# Pop register (while DISCARDING content of extended register)
.macro POPX reg
POPX_COMMON \reg, 0
.endm

# Pop register (while PRESERVING content of extended register)
# Note that this operation requires the use of EBP as a scratch register
.macro POPXP reg
POPX_COMMON \reg, 1
.endm

# Push the current SP
.macro  PUSH_SP
	movd  mm7, esp
	pand  mm7, [mmx_0000ffff]
	psllq mm6, 0x10
	por   mm6, mm7
.endm

# Pop the current SP (high word of ESP is DESTROYED)
.macro  POP_SP
	movd  esp, mm6
	psrlq mm6, 0x10
.endm

# Setup the two data quads (byte and word masks) required for stack usage
.macro SETUP_STACK_DATA
mmx_000000ff:
	.quad 0xff
mmx_0000ffff:
	.quad 0xffff
.endm
