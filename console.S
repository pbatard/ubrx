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

# Jump to a subroutine
.macro  ROM_CALL addr
	mov  sp, offset 9f	# Use a local label as we don't know the size
	jmp  \addr		# of the jmp instruction (can be 2 or 3 bytes)
9:	# see http://sourceware.org/binutils/docs-2.21/as/Symbol-Names.html
.endm

.section console, "ax"
.globl enter_console
enter_console:

print_hello:			# Print a string
	mov  si, offset hello_string
	ROM_CALL print_string

serial_repeater:		# For now the "console" is a simple serial repeater
	mov  cx, 0
	ROM_CALL readchar
	ROM_CALL putchar
	jmp  serial_repeater

hello_string:
	.string "\r\nubrx> "	# automatically NUL terminated