# Nexys A7 demo for the RV32I core.
#   LED[7:0]   number of switches that are on (popcount, computed in a function)
#   LED[15:8]  a free-running counter, so the board visibly runs
# Exercises loads/stores to I/O, a function call with a stack frame,
# branches, shifts and logic instructions.

        .equ IO_BASE, 0x80000000      # +0 LEDs (write), +4 switches (read)
        .equ STACK_TOP, 0x1000        # top of the 4 KiB on-chip RAM

        .section .text.init
        .globl _start
_start:
        li      sp, STACK_TOP
        li      s0, IO_BASE
        li      s1, 0                 # loop counter

loop:
        lw      a0, 4(s0)             # read switches
        call    popcount              # a0 = number of bits set
        srli    t0, s1, 16            # slow-moving counter bits
        andi    t0, t0, 0xff
        slli    t0, t0, 8
        or      a0, a0, t0
        sw      a0, 0(s0)             # write LEDs
        addi    s1, s1, 1
        j       loop

# a0 = popcount(a0)
popcount:
        addi    sp, sp, -16
        sw      ra, 12(sp)
        sw      s2, 8(sp)
        li      s2, 0
1:      beqz    a0, 2f
        andi    t1, a0, 1
        add     s2, s2, t1
        srli    a0, a0, 1
        j       1b
2:      mv      a0, s2
        lw      s2, 8(sp)
        lw      ra, 12(sp)
        addi    sp, sp, 16
        ret
