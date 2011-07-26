# Test whether jumps between sections work
.intel_syntax noprefix
.code16
.section section1, "a"
.globl s1
s1: .long 0
.section section2, "ax"
.globl s2
s2: jmp s1
