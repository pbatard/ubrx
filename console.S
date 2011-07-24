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
/* Constants:                                                                   */
/********************************************************************************/
OP_DUMP_ACC       = 0x3F	# '?'
OP_MOVE_IMM       = 0x23	# '#'
OP_WRMSR          = 0x2B	# '+'
OP_RDMSR          = 0x2D	# '-'
OP_CPUID          = 0x2A	# '*'
OP_EXIT           = 0x2E	# '.'
OP_ACC_TO_REG     = 0x40	# "BCDE" [42-45]
OP_REG_TO_ACC     = 0x60	# "bcde" [62-65]
OP_ACC_TO_PORT    = 0x58	# "XYZ" [58-5A]
OP_PORT_TO_ACC    = 0x78	# "xyz" [78-7A]
OP_ACC_TO_MEM     = 0x48	# "HIJ" [48-4A]
OP_MEM_TO_ACC     = 0x68	# "hij" [68-6A]

REG_EBX           = 0x02
REG_ECX           = 0x03
REG_EDX           = 0x04
REG_CR0           = 0x05

SIZE_BYTE         = 0x00
SIZE_WORD         = 0x01
SIZE_LONG         = 0x02

# Note: the last EAX transfered will be used as RAM/CAR address


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

# RoC (RISC on CISC)
# We use MM0, MM1, MM2 and MM3 in lieu of EAX/EBX/ECX/EDX respectively
read_command:
	xor  eax, eax
# TODO: factorise this	
	xor  cx, cx		# infinite timeout
	ROM_CALL_XS readchar
	ROM_CALL_XS putchar
	cmp  al, 0x0d
	jne  0f
	mov  al, 0x0a
	ROM_CALL_XS putchar
#	
0:	cmp  al, 0x20
	jle  read_command	# ignore carriage returns, tabs, space, etc.
	movd ebx, mm1		# 
	movd ecx, mm2		# CX/DX have been modified by reachar
	movd edx, mm3
# TODO: do that further down

# print EAX in hex
dump_acc:
	cmp  al, OP_DUMP_ACC
	jne  move_imm
	movd eax, mm0
	ROM_CALL_XS print_hex
	jmp  read_command

# move 32 bit immediate value to EAX
move_imm:
	cmp  al, OP_MOVE_IMM
	jne  cmd_wrmsr
	mov  cl, 0x08
	xor  ebx, ebx
0:	shl  ecx, 0x10
3:	xor  cx, cx		# infinite timeout
	ROM_CALL_XS readchar
	ROM_CALL_XS putchar
	cmp  al, 0x0d
	jne  1f
	mov  al, 0x0a
	ROM_CALL_XS putchar	
1:	shr  ecx, 0x10
	cmp  al, '0'		# ignore whitespaces
	jge  1f
	cmp  cl, 0x08		# a whitespace encountered after the
	je   3b			# beginning means early exit
	jmp  4f 
1:	inc  dl	
	cmp  al, 'a'
	jl   1f
	sub  al, 'a'-10
	jmp  2f
1:	cmp  al, 'A'
	jl   1f
	sub  al, 'A'-10
	jmp  2f
1:	cmp  al, '9'
	jg   1f
	sub  al, '0'
	jmp  2f
1:	mov  ebx, 0xffffffff
	jmp  read_command
2:	and  al, 0x0f
	shl  ebx, 0x04
	add  bl, al
	dec  cl
	jne  0b
4:	movd mm0, ebx		# will be restored into EAX
	jmp  read_command

# WRMSR
cmd_wrmsr:
	cmp  al, OP_WRMSR
	jne  cmd_rdmsr
	movd eax, mm0		# ECX/EDX have already been restored
	wrmsr
	jmp  read_command

# RDMSR
cmd_rdmsr:
	cmp  al, OP_RDMSR
	jne  cmd_cpuid
	rdmsr
	movd mm0, eax
	movd mm3, edx
	jmp  read_command

# CPUID
cmd_cpuid:
	cmp  al, OP_CPUID
	jne  cmd_exit
	movd eax, mm0
	cpuid
	movd mm0, eax
	movd mm1, ebx
	movd mm2, ecx
	movd mm3, edx
	jmp  read_command

# EXIT - the current value of EAX will be used as RAM/CAR base (CS:IP)
#        the current value of EBX will be used as SS:SP
cmd_exit:
	cmp  al, OP_EXIT
	jne  acc_to_reg
	# TODO
	jmp  read_command

# move EAX to one of EBX, ECX, EDX, CR0
acc_to_reg:
	mov  ah, al
	and  ah, 0xf8
	and  al, 0x07
	cmp  ah, OP_ACC_TO_REG
	jne  reg_to_acc
acc_to_ebx:
	cmp  al, REG_EBX
	jne  acc_to_ecx
	movq mm1, mm0
	jmp  read_command
acc_to_ecx:
	cmp  al, REG_ECX
	jne  acc_to_edx
	movq mm2, mm0
	jmp  read_command
acc_to_edx:
	cmp  al, REG_EDX
	jne  acc_to_cr0
	movq mm3, mm0
	jmp  read_command
acc_to_cr0:
	cmp  al, REG_CR0
	jne  read_command
	movd eax, mm0
	mov  cr0, eax
	jmp  read_command

# move one of EBX, ECX, EDX, CR0 to EAX
reg_to_acc:
	cmp  ah, OP_REG_TO_ACC
	jne  acc_to_port
ebx_to_acc:
	cmp  al, REG_EBX
	jne  ecx_to_acc
	movq mm0, mm1
	jmp  read_command
ecx_to_acc:
	cmp  al, REG_ECX
	jne  edx_to_acc
	movq mm0, mm2
	jmp  read_command
edx_to_acc:
	cmp  al, REG_EDX
	jne  cr0_to_acc
	movq mm0, mm3
	jmp  read_command
cr0_to_acc:
	cmp  al, REG_CR0
	jne  read_command
	mov  eax, cr0
	movd mm0, eax

# Output AL/AX/EAX to the port indexed by DX
acc_to_port:
	mov  bl, al
	cmp  ah, OP_ACC_TO_PORT
	jne  port_to_acc
	movd eax, mm0
	movd edx, mm3
out_byte:
	cmp  bl, SIZE_BYTE
	jne  out_word
	out  dx, al
	jmp  read_command
out_word:
	cmp  bl, SIZE_WORD
	jne  out_long
	out  dx, ax
	jmp  read_command
out_long:
	cmp  bl, SIZE_LONG
	jne  read_command
	out  dx, eax
	jmp  read_command	

# Input the port indexed by DX to AL/AX/EAX
port_to_acc:
	cmp  ah, OP_PORT_TO_ACC
	jne  acc_to_mem
	movd edx, mm3
in_byte:
	cmp  bl, SIZE_BYTE
	jne  in_word
	in   al, dx
	jmp  in_acc
in_word:
	cmp  bl, SIZE_WORD
	jne  in_long
	in   ax, dx
	jmp  in_acc
in_long:
	cmp  bl, SIZE_LONG
	jne  read_command
	in   eax, dx
in_acc:
	movd mm0, eax
	jmp  read_command

# Move AL/AX/EAX to the memory address pointed by EDX
acc_to_mem:
	cmp  ah, OP_ACC_TO_MEM
	jne  mem_to_acc
	# EDX (MM3) is used a pointer to the memory location (=> ES:DI)
	movd eax, mm3
	mov  di, ax
	xor  ax, ax
	shr  eax, 0x04		# convert to segment
	mov  es, ax
accmem_byte:
	cmp  bl, SIZE_BYTE
	jne  accmem_word
	mov  [di], al
	jmp  read_command
accmem_word:
	cmp  bl, SIZE_WORD
	jne  accmem_long
	mov  [di], ax
	jmp  read_command
accmem_long:
	cmp  bl, SIZE_LONG
	jne  read_command
	mov  [di], eax
	jmp  read_command

# Move the content of the memory address pointed by EDX into AL/AX/EAX
mem_to_acc:
	cmp  ah, OP_MEM_TO_ACC
	jne  read_command
	movd eax, mm3
	mov  di, ax
	xor  ax, ax
	shr  eax, 0x04		# convert to segment
	mov  es, ax
memacc_byte:
	cmp  bl, SIZE_BYTE
	jne  memacc_word
	mov  al, [di]
	jmp  read_command
memacc_word:
	cmp  bl, SIZE_WORD
	jne  memacc_long
	mov  ax, [di]
	jmp  read_command
memacc_long:
	cmp  bl, SIZE_LONG
	jne  read_command
	mov  eax, [di]
	jmp  read_command

prompt_string:
	.string "\r\ns/u/b/q> "
	# 's'etup, 'u'pload, 'b'ranch, 'q'uit