# Design notes

Why the core is built the way it is, and how each part is verified.

## 1. Single cycle, Harvard

Each clock edge retires one instruction: fetch, decode, register read,
execute, memory access and write-back all happen combinationally within the
cycle, and the PC, register file and data memory update on the edge.

* **CPI = 1, but a long cycle.** The critical path runs instruction memory
  read -> decode -> register read -> ALU (address) -> data memory read ->
  load alignment -> register-file write setup. Every instruction pays for
  the slowest one (a load). The pipelined version splits this path into five
  stages.
* **Separate instruction and data ports** let an instruction fetch and a data
  access happen in the same cycle. On the FPGA both ports map onto one
  dual-port RAM, so code and data still share one address space.
* **Combinational memory reads** are what make single-cycle possible, and
  they force distributed RAM (LUTRAM) on the FPGA: block RAM has a
  registered read. This is one of the main reasons real cores are pipelined.

## 2. Decoder

`riscv_decoder.sv` is a single combinational case on the opcode. It produces:
ALU operation, operand selects (A: rs1 / PC / zero; B: rs2 / immediate),
immediate format, write-back select (ALU / load / PC+4), and the
reg-write, mem-read, mem-write, branch, JAL, JALR, ECALL/EBREAK and illegal
flags.

* LUI is executed as `0 + imm` and AUIPC as `PC + imm`, so neither needs a
  special path.
* JALR uses the ALU to form `rs1 + imm`; bit 0 is then cleared, as the ISA
  requires.
* Everything that is not RV32I is **illegal**: reserved funct3/funct7 values,
  CSR instructions, FENCE.I, compressed encodings, the all-zero and all-ones
  words. When `illegal` is set every side-effect control is forced off, so an
  illegal instruction cannot write anything even before the trap logic acts.

## 3. Branches and jumps

Branch comparison is separate from the ALU (`==`, signed `<` and unsigned
`<` on rs1/rs2), so the ALU is free to compute nothing else and the compare
runs in parallel with it. The target is `PC + imm` for branches and JAL,
`(rs1 + imm) & ~1` for JALR.

## 4. Loads and stores

The data bus is word-addressed with a 4-bit byte mask (`riscv_lsu.sv`):

* **Stores** replicate the byte or halfword across all lanes (`{4{rs2[7:0]}}`)
  and the mask selects which lanes the memory writes. No shifter is needed.
* **Loads** shift the addressed lanes down and sign- or zero-extend.
* **Misaligned** halfword/word accesses are detected and trap. The ISA lets
  an implementation either support them or trap; trapping keeps the bus
  simple (one access per instruction).

## 5. Traps

There are no CSRs or interrupts, so the core's trap behaviour is to stop:
`halted` rises and no architectural state changes for the trapping
instruction (no register write, no store, PC unchanged). Trap causes:
illegal instruction, ECALL, EBREAK, misaligned load/store, and a taken
branch or jump whose target is not 4-byte aligned. Test programs end with
ECALL. Adding Zicsr (mtvec, mepc, mcause) would turn this into a proper trap
handler entry; that is a natural next step.

## 6. Register file

32 x 32 bits, two asynchronous read ports, one write port, no reset (RISC-V
does not define register values at reset, and software initialises what it
uses). x0 is never stored: reads of register 0 return zero and writes are
dropped. On Xilinx this maps to distributed RAM (Yosys: 12 RAM32M).

## 7. RVFI trace port

With `RISCV_FORMAL` defined, the core outputs one RVFI record per retired
instruction: the instruction, PC before and after, source register addresses
and values, destination register and value, memory address, read and write
masks and data, and the trap flag. The record is registered, so it describes
the instruction that retired on the previous edge.

The same port serves two purposes:

* **riscv-formal** connects to it and checks the core against a formal
  model of every instruction.
* **The cocotb lockstep test** reads it every cycle and compares it with the
  Python ISS.

## 8. Verification

### riscv-tests (`make isa`)
The official RV32UI programs, built against a minimal environment
(`tests/env/riscv_test.h`). The standard environment needs CSRs, so ours
reports through `gp` instead: 1 for pass, `(test << 1) | 1` for a failure,
then ECALL stops the core. `tb/tb_isa.sv` reads `gp` once the core halts.
Skipped: `fence_i` (Zifencei) and `ma_data` (misaligned accesses trap here).

### Random lockstep (`make random`)
* `tb/rvgen.py` generates programs that are guaranteed to terminate: random
  register contents, then a random mix of every instruction type with only
  forward control flow, loads and stores through a base register pointing at
  a data region, and a final ECALL. A second mode mixes in misaligned
  accesses, misaligned jumps and illegal instructions.
* `tb/iss.py` is an instruction-set simulator written from the ISA manual,
  independent of the RTL.
* `tb/test_random.py` runs each program on both and compares every RVFI
  field of every retired instruction. Fields that are don't-cares for an
  instruction (for example store data on an ADD) may be X; a field that
  matters being X is a failure.
* 69 coverage bins (every instruction, both branch outcomes, every byte lane,
  every trap type, writes to x0, JALR with bit 0 set) must all be hit.
* The generator had a real bug that the test exposed: a branch could land on
  a JALR and skip the AUIPC that set its base register. Both models agreed
  (they jumped to the same random address), so this showed up as an
  undefined instruction fetch, and the fix moved such targets onto the
  AUIPC.

### riscv-formal (`make formal`)
Checks generated for `isa rv32i`:

| Check | Meaning |
|---|---|
| `insn_*` (37) | For each instruction: from any state, with any memory contents, the retired result (registers, memory, next PC, trap) equals the ISA model |
| `reg` | A register read returns the value of the most recent write to it |
| `pc_fwd`, `pc_bwd` | Each instruction's PC equals the previous instruction's next PC |
| `unique` | No instruction retires twice |
| `causal` | A register value is not used before it is produced |
| `ill` | Illegal instructions trap |
| `cover` | Four instructions retire (the checks are not vacuous) |

Instruction and data memory contents are free inputs, so each check covers
every possible program.

### Mutation checks
Injected bugs, each caught: BNE behaving as BEQ (39 riscv-tests fail), BGE
compared unsigned (`insn_bge` fails in riscv-formal, which also produces a
counterexample trace), LH not sign-extending (random test fails on the
first such load).

## 9. FPGA top level

* **Clock from the MMCM**, not from a counter in the fabric. A divided clock
  made from a flip-flop is not on a clock buffer, adds skew and is a common
  review comment.
* **Reset**: asserted asynchronously, released synchronously (2-flop
  synchroniser), and held until the MMCM has locked.
* **Memory map**: RAM from 0x0000_0000, LEDs at 0x8000_0000, switches at
  0x8000_0004 (address bit 31 selects I/O).
* All 35 pin assignments were checked against Digilent's master XDC.

## 10. Questions to be ready for

* Walk through the datapath for `lw`, `sw`, `beq` and `jalr`.
* What is the critical path, and why does the core need distributed RAM?
* Why replicate store data instead of shifting it?
* Why trap on misaligned accesses? What would supporting them cost?
* What does riscv-formal prove that riscv-tests do not? What do riscv-tests
  catch that a formal check with a short depth might not?
* How does the random test avoid infinite loops, and what does the coverage
  tell you?
* How would you add CSRs and real trap handling?
* What changes in the pipelined version (hazards, forwarding, stalls)?
