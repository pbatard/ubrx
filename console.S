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
/* GNU Assembler Settings:                                                      */
/********************************************************************************/
.intel_syntax noprefix	# Use Intel assembler syntax (same as IDA Pro)
.code16			# After reset, the x86 CPU is in real/16 bit mode
/********************************************************************************/
# Can't use externally defined macros in an include...  :(
JMP_WORKAROUND_OFFSET = 2*JMP_WORKAROUND	# used in macros.inc

.include "config.inc"
.include "macros.inc"	# macros.inc must be included after config.inc


/********************************************************************************/
/* Constants:                                                                   */
/********************************************************************************/
# Script/setup mode commands
OP_COMMENT        = '#'
OP_DUMP_ACC       = '?'
OP_MOVE_IMM       = '$'
OP_DIVISOR        = ':'
OP_WRMSR          = 'm'
OP_RDMSR          = 'M'
OP_CPUID          = '*'
OP_INVD           = '!'
OP_EXIT           = '.'
OP_READ_RANGE     = '<'
OP_WRITE_RANGE    = '>'
OP_XIP_TRIGGER    = '%'
OP_AND            = '&'
OP_OR             = '|'
OP_ACC_TO_REG     = 'a' & 0xf8	# "abcd" [61-64]
OP_REG_TO_ACC     = 'A' & 0xf8	# "ABCD" [41-44]
OP_ACC_TO_PORT    = 'p'		# "pqr" [70-72]
OP_PORT_TO_ACC    = 'P'		# "PQR" [50-52]
OP_ACC_TO_MEM     = 'x'		# "xyz" [78-7A]
OP_MEM_TO_ACC     = 'X'		# "XYZ" [58-5A]
.if ENDIANNESS_SUPPORT
OP_LITTLE_ENDIAN  = 'l'
OP_BIG_ENDIAN     = 'L'
.endif
# Register sources/destinations
REG_CR0           = 'a' & 0x07
REG_EBX           = 'b' & 0x07
REG_ECX           = 'c' & 0x07
REG_EDX           = 'd' & 0x07
# Operation size for in/out/mov
SIZE_BYTE         = 0x00
SIZE_WORD         = 0x01
SIZE_LONG         = 0x02
# Constants for the baudrate divisor change
COM_DLL           = 0x00	# Baud Rate Divisor LSB (if DLAB is set)
COM_DLM           = 0x01	# Baud Rate Divisor MSB (if DLAB is set)
COM_LCR           = 0x03	# Line Control Register


/********************************************************************************/
/* console:                                                                     */
/* process serial input and script commands.                                    */
/********************************************************************************/

.section console, "ax"
.globl enter_console
enter_console:
# TODO: move current SIO base, type, LDN and COM base to mmx regs?
	pxor mm0, mm0
	pxor mm1, mm1
	pxor mm2, mm2
	pxor mm3, mm3
	pxor mm4, mm4		# flags
display_prompt:
	mov  si, offset prompt_string
	ROM_CALL_XS print_string
	
major_cmd:
	ROM_CALL_BP read_echo
	cmp  al, 's'		# direct hardware setup
	je   hw_setup
	cmp  al, 'u'		# upload to CAR/RAM through Y-modem
#	je   ymodem_upload
	cmp  al, 'r'		# run program in CAR/RAM
	jne  0f
	ROM_CALL_BP newline
	jmp  run_prog
0:	cmp  al, 'q'		# quit to normal BIOS
#	je   start_bios
	cmp  al, 0x0a
	je   display_prompt
	jmp  major_cmd

run_prog:
	movd eax, mm1		# EBX = 32 bit stack pointer
	mov  sp, ax
	xor  ax, ax
	shr  eax, 0x04		# convert to segment
	mov  ss, ax
	DIAG 0x81
	# perform stack test
	mov  eax, 0x55AA55AA
	push eax
	push eax
	push eax
	push eax
	pop  ebx
	pop  ebx
	pop  ebx
	pop  ebx
	cmp  eax, ebx
	jne  display_prompt
	# Now that we have a stack, we can make good use of it
	# to jump to a user specified subroutine
	DIAG 0x82
	push cs			# push CS:IP for subroutine retf
	push offset 0f
	# Easiest way to issue a dynamic far call is to just
	# push the destination CS:IP and issue a retf
	movd eax, mm0		# EAX = dest CS:IP
	mov  ebx, eax
	xor  bx, bx
	shr  ebx, 0x04		# convert to CS
	push bx
	push ax
	xor  eax, eax
	cpuid			# serializing instruction => update cache
	retf			# far call to the target subroutine
				# NB: the subroutine must end with retf as well
0:	DIAG 0x83
	mov  ax, cs
	mov  ss, ax
	jmp  display_prompt

# RoC (RISC on CISC)
# We use MM0, MM1, MM2 and MM3 in lieu of EAX, EBX, ECX, EDX respectively
hw_setup:
	ROM_CALL_BP newline
	xor  ebp, ebp
read_command:
	ROM_CALL_BP read_echo
read_command_have_char:
	cmp  al, 0x0a		# CR and LF reset the comment flag
	jne  0f
	xor  ebp, ebp		# comment flag = OFF
0:	cmp  al, 0x20
	jle  read_command	# ignore tabs, space, etc.
	xor  bp, bp
	or   ebp, ebp		# comment flag ON?
	jne  read_command	# yes => ignore to EOL
	cmp  al, OP_COMMENT	# comment start?
	jne  0f	
	not  ebp		# comment flag = ON
	jmp  read_command
0:	movd ebx, mm1
	movd ecx, mm2
	movd edx, mm3

# print EAX in hex
dump_acc:
	cmp  al, OP_DUMP_ACC
	jne  move_imm
	movd eax, mm0
	ROM_CALL_XS print_hex
	jmp  read_command

# move 32 bit immediate value to EAX or AND/OR with existing
move_imm:
	cmp  al, OP_MOVE_IMM
	je   0f
	cmp  al, OP_AND
	je   0f
	cmp  al, OP_OR
	jne  cmd_divisor
0:	mov  ch, al
	mov  cl, 0x08
	xor  ebx, ebx
read_digit:
	shl  ecx, 0x10
	ROM_CALL_BP read_echo
	shr  ecx, 0x10
	cmp  al, 'a'
	jl   0f
	cmp  al, 'f'
	jg   not_a_digit
	sub  al, 'a'-10
	jmp  1f
0:	cmp  al, 'A'
	jl   0f
	cmp  al, 'F'
	jg   not_a_digit
	sub  al, 'A'-10
	jmp  1f
0:	cmp  al, '0'
	jl   not_a_digit
	cmp  al, '9'
	jg   not_a_digit
	sub  al, '0'
1:	shl  ebx, 0x04
	add  bl, al
	dec  cl
	cmp  cl, 0x00
	je   final_result
	jmp  read_digit

not_a_digit:
	cmp  cl, 0x08		# allow tab or space at the beginning of the data
	jne  final_result
	cmp  al, 0x09
	je   read_digit
	cmp  al, ' '
	je   read_digit
	cmp  al, OP_MOVE_IMM	# also allow extra immediate value prefixes
	je   read_digit

final_result:
	cmp  ch, OP_MOVE_IMM
	je   1f
	movd edx, mm0
	cmp  ch, OP_AND	
	jne  0f
	and  ebx, edx
	jmp  1f
0:	or   ebx, edx
1:	movd mm0, ebx		# will be restored into EAX
	cmp  cl, 0x00
	jne  read_command_have_char
	jmp  read_command

# Change the baudrate divisor
cmd_divisor:
	cmp  al, OP_DIVISOR
	jne  cmd_invd
	mov  dx, COM_BASE + COM_LCR
	mov  al, 0x80		# Set divisor access
	out  dx, al
	mov  dx, COM_BASE + COM_DLL
	movd eax, mm0
	out  dx, al
	inc  dx
	mov  al, ah
	out  dx, al
	mov  dx, COM_BASE + COM_LCR
	mov  al, 0x03		# Unset divisor access. Set 8N1 mode
	out  dx, al
	jmp  read_command

# INVD
cmd_invd:
	cmp  al, OP_INVD
	jne  cmd_wrmsr
	invd
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
	jne  cmd_xip
	movd eax, mm0
	cpuid
	movd mm0, eax
	movd mm1, ebx
	movd mm2, ecx
	movd mm3, edx
	jmp  read_command

# Trigger XIP caching mode by executing a far ret instruction
# If you want a serial connection that doesn't suck, you really want XIP
cmd_xip:
	cmp  al, OP_XIP_TRIGGER
.if ENDIANNESS_SUPPORT
	jne  cmd_big_endian
.else
	jne  cmd_fill_range
.endif
	mov  sp, offset 0f
	retf			# FAR RET gets cached XIP going
0:	.word read_command
	.word 0xf000		# current CS should still be 0xf000 at this stage

.if ENDIANNESS_SUPPORT
cmd_big_endian:
	cmp  al, OP_BIG_ENDIAN
	jne  cmd_little_endian
	movd ebx, mm4
	mov  bl, 0x01
	movd mm4, ebx
	jmp  read_command

cmd_little_endian:
	cmp  al, OP_LITTLE_ENDIAN
	jne  cmd_fill_range
	movd ebx, mm4
	xor  bl, bl
	movd mm4, ebx
	jmp  read_command
.endif

# Read memory range 
cmd_fill_range:
	cmp  al, OP_READ_RANGE
	je   0f
	cmp  al, OP_WRITE_RANGE
	jne  cmd_exit
0:	mov  bl, al
	movd eax, mm0
	mov  di, ax
	xor  ax, ax
	shr  eax, 4
	mov  es, ax
	movd ecx, mm2
	shr  ecx, 2
	cmp  bl, OP_READ_RANGE
	jne  cmd_write_range
	# NB rep lods & rep stos don't work here
0:	mov  eax, es:[di]
	add  di, 4
	loop 0b
	jmp  read_command
cmd_write_range:
	mov  eax, 0xcbcbcbcb	# RETF
0:	mov  es:[di], eax
	add  di, 4
	loop 0b
	jmp  read_command

# EXIT - the current value of EAX will be used as RAM/CAR base (CS:IP)
#        the current value of EBX will be used as SS:SP
cmd_exit:
	cmp  al, OP_EXIT
	jne  acc_to_reg
	ROM_CALL_BP newline
	jmp  display_prompt

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
	jmp  0f
acc_to_ecx:
	cmp  al, REG_ECX
	jne  acc_to_edx
	movq mm2, mm0
	jmp  0f
acc_to_edx:
	cmp  al, REG_EDX
	jne  acc_to_cr0
	movq mm3, mm0
	jmp  0f
acc_to_cr0:
	cmp  al, REG_CR0
	jne  0f
	movd eax, mm0
	mov  cr0, eax
0:	jmp  read_command

# move one of EBX, ECX, EDX, CR0 to EAX
reg_to_acc:
	cmp  ah, OP_REG_TO_ACC
	jne  acc_to_port
ebx_to_acc:
	cmp  al, REG_EBX
	jne  ecx_to_acc
	movq mm0, mm1
	jmp  0f
ecx_to_acc:
	cmp  al, REG_ECX
	jne  edx_to_acc
	movq mm0, mm2
	jmp  0f
edx_to_acc:
	cmp  al, REG_EDX
	jne  cr0_to_acc
	movq mm0, mm3
	jmp  0f
cr0_to_acc:
	cmp  al, REG_CR0
	jne  0f
	mov  eax, cr0
	movd mm0, eax
0:	jmp  read_command

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
	jmp  1f
out_word:
	cmp  bl, SIZE_WORD
	jne  out_long
.if ENDIANNESS_SUPPORT
	movd ebx, mm4
	or   bl, bl
	je   0f
	xchg ah, al
.endif
0:	out  dx, ax
	jmp  1f
out_long:
	cmp  bl, SIZE_LONG
	jne  1f
.if ENDIANNESS_SUPPORT
	movd ebx, mm4
	or   bl, bl
	je   0f
	bswap eax
.endif	
0:	out  dx, eax
1:	jmp  read_command

# Input the port indexed by DX to AL/AX/EAX
port_to_acc:
	cmp  ah, OP_PORT_TO_ACC
	jne  acc_to_mem
	movd edx, mm3
in_byte:
	cmp  bl, SIZE_BYTE
	jne  in_word
	in   al, dx
	jmp  0f
in_word:
	cmp  bl, SIZE_WORD
	jne  in_long
	in   ax, dx
.if ENDIANNESS_SUPPORT
	movd ebx, mm4
	or   bl, bl
	je   0f
	xchg ah, al
.endif
	jmp  0f
in_long:
	cmp  bl, SIZE_LONG
	jne  1f
	in   eax, dx
.if ENDIANNESS_SUPPORT
	movd ebx, mm4
	or   bl, bl
	je   0f
	bswap eax
.endif
0:	movd mm0, eax
1:	jmp  read_command

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
	movd eax, mm0
accmem_byte:
	cmp  bl, SIZE_BYTE
	jne  accmem_word
	mov  es:[di], al
	jmp  1f
accmem_word:
	cmp  bl, SIZE_WORD
	jne  accmem_long
.if ENDIANNESS_SUPPORT
	movd ebx, mm4
	or   bl, bl
	je   0f
	xchg ah, al
.endif
0:	mov  es:[di], ax
	jmp  1f
accmem_long:
	cmp  bl, SIZE_LONG
	jne  1f
.if ENDIANNESS_SUPPORT
	movd ebx, mm4
	or   bl, bl
	je   0f
	bswap eax
.endif
0:	mov  es:[di], eax
1:	jmp  read_command

# Move the content of the memory address pointed by EDX into AL/AX/EAX
mem_to_acc:
	cmp  ah, OP_MEM_TO_ACC
	jne  1f
	movd eax, mm3
	mov  di, ax
	xor  ax, ax
	shr  eax, 0x04		# convert to segment
	mov  es, ax
memacc_byte:
	cmp  bl, SIZE_BYTE
	jne  memacc_word
	mov  al, es:[di]
	jmp  0f
memacc_word:
	cmp  bl, SIZE_WORD
	jne  memacc_long
	mov  ax, es:[di]
.if ENDIANNESS_SUPPORT
	movd ebx, mm4
	or   bl, bl
	je   0f
	xchg ah, al
.endif
	jmp  0f
memacc_long:
	cmp  bl, SIZE_LONG
	jne  1f
	mov  eax, es:[di]
.if ENDIANNESS_SUPPORT
	movd ebx, mm4
	or   bl, bl
	je   0f
	bswap eax
.endif
0:	movd mm0, eax
1:	jmp  read_command


/********************************************************************************/
/* Subroutines:                                                                 */
/********************************************************************************/

newline:
	mov  al, 0x0d
	ROM_CALL_XS putchar
	mov  al, 0x0a
	ROM_CALL_XS putchar
	jmp  bp

read_echo:
	xor  cx, cx		# infinite timeout
	ROM_CALL_XS readchar
	cmp  al, 0x0a		# LF -> CR
	je   newline
	cmp  al, 0x0d		# LF -> CR
	je   newline
	ROM_CALL_XS putchar
	jmp  bp

prompt_string:
	.string "s/u/r/q> "
