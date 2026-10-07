# RV32I RISC-V Processor

A single-cycle RISC-V core implementing the complete **RV32I** base integer
instruction set, written from scratch in SystemVerilog and verified three
independent ways:

* **riscv-formal**: every instruction formally checked against the ISA
  specification, plus register-file, PC and liveness-style consistency checks
  (44/44 pass)
* **riscv-tests**: the official RV32UI test suite (40/40 pass)
* **Random lockstep simulation**: constrained-random programs run on the core
  and on an independent Python instruction-set simulator, compared instruction
  by instruction through the RISC-V Formal Interface (RVFI), with functional
  coverage

It runs on a Digilent Nexys A7 board with a demo program. Design notes:
[docs/DESIGN.md](docs/DESIGN.md).

## Features

| | |
|---|---|
| ISA | RV32I: all 37 computational, memory and control-flow instructions, plus FENCE (no-op), ECALL and EBREAK |
| Microarchitecture | single-cycle, Harvard (separate instruction and data ports), CPI = 1 |
| Memory interface | word-addressed data bus with byte write mask; byte/halfword alignment and sign extension in the core |
| Traps | illegal instructions, ECALL/EBREAK, misaligned loads/stores and misaligned jump/branch targets stop the core with no state change |
| Trace | RVFI port (`RISCV_FORMAL`), one record per retired instruction |
| FPGA | Nexys A7 top level: MMCM clock, reset synchroniser, on-chip RAM, LEDs and switches as memory-mapped I/O |

## Datapath

```
        +------+   instr   +---------+  ctrl   +-------------------------------+
  +---->|  PC  |---------->| decoder |-------->|  ALU-A: rs1 / PC / 0          |
  |     +------+  imem     | imm gen |  imm    |  ALU-B: rs2 / imm             |
  |        |               +---------+         |  ALU -> result / address      |
  |        |                    |              +-------------------------------+
  |        |               +---------+  rs1,rs2      |              |
  |        |               | regfile |---------------+              v
  |        |               | 32 x 32 |<---- write-back ----+   +----------+
  |        |               +---------+   ALU / load / PC+4 |   |   LSU    |<--> dmem
  |        |                    |                          +---| align,   |
  |        v                    v                              | mask,    |
  |   +---------+         +-----------+                        | extend   |
  +---| next PC |<--------| branch    |                        +----------+
      | PC+4 /  |         | compare   |
      | target  |         +-----------+
      +---------+
```

## Verification

| Method | What it shows | Result |
|---|---|---|
| riscv-formal (SymbiYosys + Yices) | For every instruction, from any reachable state and any memory contents, the retired result matches the formal ISA model; register reads return the last write; the PC sequence is consistent; illegal instructions trap | **44 / 44 checks pass** |
| riscv-tests RV32UI | The official per-instruction test programs | **40 / 40 pass** |
| Random lockstep (cocotb) | Random programs on the RTL and on a Python ISS give identical RVFI traces: PC, next PC, instruction, trap, register write, memory address, masks and store data | 92,829 instructions over 300 programs, all coverage bins hit (69 bins: every instruction, taken and not-taken branches, every byte lane, every trap type, writes to x0) |
| Mutation checks | Breaking BNE fails 39 riscv-tests; making BGE unsigned fails `insn_bge` in riscv-formal; removing LH sign extension fails the random test | caught |
| Verilator `-Wall` | core with and without RVFI, FPGA top | clean |

Two riscv-tests are skipped on purpose: `fence_i` (self-modifying code needs
the Zifencei extension) and `ma_data` (this core traps on misaligned accesses,
which the ISA allows).

## FPGA (Nexys A7)

`fpga/top_nexys_a7.sv` runs the core at 50 MHz from the board's MMCM with
4 KiB of on-chip RAM. The demo program `sw/demo.S` shows the number of
switches that are on in LED[7:0] (computed by a function with a stack frame)
and a running counter in LED[15:8]. The red LED16 lights if the core traps.

Vivado: create a project for `xc7a100tcsg324-1`, add `rtl/*.sv`,
`rtl/rv32i_defs.svh`, `fpga/top_nexys_a7.sv`, `fpga/demo.hex` and
`fpga/nexys_a7.xdc`, set `top_nexys_a7` as top and generate the bitstream.
`make fpga-sim` checks the same top level and program in simulation.

### Resources

Yosys `synth_xilinx` estimate for the core alone: **962 LUTs, 33 flip-flops,
12 RAM32M** (the register file in distributed RAM), 50 CARRY4. Vivado
utilisation and timing will be added here after implementation.

## Running it

```
git submodule update --init      # riscv-tests and riscv-formal
make lint                         # Verilator -Wall
make isa                          # riscv-tests RV32UI
make random                       # cocotb lockstep test (make -C tb SEED=7 N=300 for more)
make formal                       # riscv-formal
make fpga-sim                     # board top level + demo program
make synth                        # Yosys resource estimate
```

Requires Icarus Verilog 12, Verilator 5, Yosys, SymbiYosys with Yices,
`riscv64-unknown-elf-gcc` and Python 3 with `cocotb >= 2.0`. CI runs all of
it on every push.

## Repository layout

```
rtl/        riscv_core.sv (datapath + RVFI), riscv_decoder.sv, riscv_alu.sv,
            riscv_imm_gen.sv, riscv_regfile.sv, riscv_lsu.sv, rv32i_defs.svh
tb/         iss.py (reference ISS), rvgen.py (random programs),
            test_random.py (cocotb lockstep), tb_isa.sv, tb_rvfi.sv, sim_mem.sv
tests/      run_isa_tests.py, env/ (minimal test environment), riscv-tests/
formal/     riscv-formal wrapper and configuration, run.sh, riscv-formal/
fpga/       Nexys A7 top level, constraints, demo image, testbench
sw/         demo program and linker script
docs/       DESIGN.md
```

## Changes from v1

The first version supported only part of RV32I and was tested with one
five-instruction program:

* every branch behaved as BEQ (BNE/BLT/BGE/BLTU/BGEU were wrong)
* I-type ALU instructions other than ADDI silently executed as ADDI
* XOR, shifts, SLT/SLTU (register forms), LUI, AUIPC, JAL, JALR, byte and
  halfword loads/stores were missing
* undefined instructions were not detected

All of these are now implemented and verified as described above.
