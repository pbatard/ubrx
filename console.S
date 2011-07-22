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

# Fixes a binutil/ld bug where the address if off by 2 on cross section jumps
.macro  JMP_XS addr
	jmp  \addr + 2
.endm

# Jump to a subroutine
.macro  ROM_CALL addr
	mov  sp, offset 9f	# Use a local label as we don't know the size
	jmp  \addr		# of the jmp instruction (can be 2 or 3 bytes)
9:	# see http://sourceware.org/binutils/docs-2.21/as/Symbol-Names.html
.endm
.macro  ROM_CALL_XS addr
	mov  sp, offset 9f
	JMP_XS \addr
9:
.endm

.section console, "ax"
.globl enter_console
enter_console:
	mov  si, offset prompt_string
	ROM_CALL_XS print_string

read_command:
	movd mm0, eax		# A stack won't do here as we are trying to keep
	movd mm1, ebx		# the footprint low and we may "unstack" in any order
	movd mm2, ecx
	movd mm3, edx
	mov  cx, 0		# infinite timeout
	ROM_CALL_XS readchar
	mov  ah, al
	and  ah, 0xf0
	and  al, 0x0f
dump_eax:
	cmp  ah, 0x20
	jne  mov_imm_eax
	movd eax, mm0
	ROM_CALL_XS print_hex
	jmp  rest
mov_imm_eax:
	cmp  ah, 0x30
	jne  mov_eax_dst
	mov  cl, 0x04
0:	shl  ecx, 0x10
	mov  cx, 0		# infinite timeout
	ROM_CALL_XS readchar
	shl  ebx, 0x08
	mov  bl, al
	shr  ecx, 0x10
	dec  cl
	jne  0b
	movd mm0, ebx		# will be restored into EAX
	jmp  rest
mov_eax_dst:
rest:
	movd eax, mm0
	movd ebx, mm1
	movd ecx, mm2
	movd edx, mm3
	jmp  read_command

prompt_string:
	.string "\r\nubrx> "	# automatically NUL terminated