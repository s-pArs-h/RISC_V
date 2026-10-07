// Minimal riscv-tests environment for a core without CSRs or trap handlers.
//
// The official "p" environment sets up machine-mode CSRs and reports results
// through a trap handler. This core has no CSRs, so instead:
//   pass: gp (TESTNUM) = 1, then ECALL, which halts the core
//   fail: gp = (failing test number << 1) | 1, then ECALL
// The testbench reads gp after the core halts.
#ifndef _ENV_MINIMAL_H
#define _ENV_MINIMAL_H

#define RVTEST_RV32U .macro init; .endm
#define RVTEST_RV64U .macro init; .endm
#define TESTNUM gp

#define RVTEST_CODE_BEGIN                       \
        .section .text.init;                    \
        .align  6;                              \
        .globl _start;                          \
_start:                                         \
        li TESTNUM, 0;

#define RVTEST_CODE_END unimp

#define RVTEST_PASS                             \
        fence;                                  \
        li TESTNUM, 1;                          \
        ecall

#define RVTEST_FAIL                             \
        fence;                                  \
1:      beqz TESTNUM, 1b;                       \
        sll TESTNUM, TESTNUM, 1;                \
        or TESTNUM, TESTNUM, 1;                 \
        ecall

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                       \
        EXTRA_DATA                              \
        .pushsection .tohost,"aw",@progbits;    \
        .align 6; .global tohost; tohost: .dword 0;         \
        .align 6; .global fromhost; fromhost: .dword 0;     \
        .popsection;                            \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
