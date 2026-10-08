# RV32I RISC-V Processors

Two RISC-V cores implementing the complete **RV32I** base integer instruction
set, written from scratch in SystemVerilog:

* **`riscv_core`**: single-cycle, CPI 1
* **`riscv_pipeline`**: classic 5-stage pipeline (IF, ID, EX, MEM, WB) with
  forwarding, load-use stalls, branch flushing, precise traps and
  block-RAM-friendly synchronous memories

Both share the decoder, ALU, immediate generator, register file and
load/store unit, have identical ports, and are verified three independent ways:

* **riscv-formal**: every instruction formally checked against the ISA
  specification, plus register, PC, uniqueness and causality checks
  (44/44 on each core)
* **riscv-tests**: the official RV32UI suite (40/40 on each core)
* **Random lockstep simulation**: constrained-random programs compared
  instruction by instruction with an independent Python ISS through the
  RISC-V Formal Interface (RVFI), with functional coverage including every
  pipeline hazard path

Both run on a Digilent Nexys A7 board. Design notes: [docs/DESIGN.md](docs/DESIGN.md).

## The two cores

| | `riscv_core` | `riscv_pipeline` |
|---|---|---|
| Structure | single cycle | IF, ID, EX, MEM, WB |
| Memory reads | combinational (distributed RAM) | registered, data one cycle later (block RAM) |
| Hazards | none | forwarding MEM->EX and WB->EX, WB->ID bypass, 1-cycle load-use stall |
| Branches | resolved in the same cycle | predict not-taken, resolved in EX, 1-cycle penalty when taken |
| CPI on riscv-tests | 1.00 | 1.07 (pipeline fill, taken branches, load-use stalls) |
| Board clock (default) | 40 MHz | 80 MHz |
| Yosys estimate (Artix-7) | 962 LUT, 33 FF, 12 RAM32M | 1424 LUT, 333 FF, 12 RAM32M |

Common to both: all 37 computational, memory and control-flow instructions
plus FENCE (no-op), ECALL and EBREAK; word-addressed data bus with byte
write mask; traps on illegal instructions, ECALL/EBREAK, misaligned
loads/stores and misaligned jump/branch targets, which stop the core without
changing state; RVFI trace port under `RISCV_FORMAL`.

### Pipeline

```
          IF             ID                 EX                   MEM            WB
     +----------+   +-----------+   +------------------+   +-----------+   +---------+
PC ->| imem addr|-->| decode    |-->| forward  ALU     |-->| load data |-->| reg     |
     | (PC+4 or |   | reg read  |   | branch compare   |   | align and |   | write,  |
     |  target) |   | hazard    |   | traps            |   | extend    |   | retire  |
     +----------+   | check     |   | dmem addr/store  |   +-----------+   +---------+
          ^         +-----------+   +------------------+         |              |
          |              ^  stall          |   ^   ^             |              |
          +--------------+-- redirect -----+   |   +-- MEM fwd --+              |
                                               +------- WB fwd -----------------+
```

## Verification

| Method | `riscv_core` | `riscv_pipeline` |
|---|---|---|
| **riscv-formal**: each instruction vs. the formal ISA model from any state with any memory contents; reg, pc_fwd, pc_bwd, unique, causal, ill, cover | **44 / 44** | **44 / 44** |
| **riscv-tests** RV32UI | **40 / 40** | **40 / 40** |
| **Random lockstep vs. Python ISS** (every RVFI field of every retired instruction) | 92,829 instructions, 69/69 coverage bins | 92,829 instructions, 78/78 bins (adds: every forwarding path, load-use stall, branch flush, trap squash, store-then-load, WB->ID bypass) |
| Verilator `-Wall` | clean | clean |

**Mutation checks**: each injected bug is caught.
- BNE behaving as BEQ: 39 riscv-tests fail.
- BGE compared unsigned: riscv-formal `insn_bge` fails with a counterexample.
- LH without sign extension: the random test fails.
- Pipeline with MEM forwarding removed: riscv-formal `reg` fails.
- Pipeline with no load-use stall: the random test and 6 riscv-tests fail.

Two riscv-tests are skipped on purpose: `fence_i` (needs the Zifencei
extension) and `ma_data` (these cores trap on misaligned accesses, which the
ISA allows).

## FPGA (Nexys A7)

`fpga/top_nexys_a7.sv` takes `PIPELINED = 0 | 1`. It provides an MMCM-generated
clock, a synchronised reset, 4 KiB of on-chip RAM, and LEDs and switches as
memory-mapped I/O (pins checked against Digilent's master XDC). The demo
`sw/demo.S` shows the number of switches that are on in LED[7:0] and a
running counter in LED[15:8]; the red LED16 lights if the core traps.

Vivado: create a project for `xc7a100tcsg324-1`, add `rtl/*.sv`,
`rtl/rv32i_defs.svh`, `fpga/top_nexys_a7.sv`, `fpga/demo.hex` and
`fpga/nexys_a7.xdc`, set `top_nexys_a7` as top (generic `PIPELINED` selects
the core) and generate the bitstream. `make fpga-sim` checks both versions in
simulation. Vivado timing and utilisation will be added here after
implementation.

## Running it

```
git submodule update --init      # riscv-tests and riscv-formal
make lint                         # Verilator -Wall
make isa                          # riscv-tests RV32UI, both cores
make random                       # cocotb lockstep (make -C tb CORE=riscv_pipeline SEED=7 N=300)
make formal                       # riscv-formal, both cores
make fpga-sim                     # board top level + demo, both cores
make synth                        # Yosys resource estimates
```

Requires Icarus Verilog 12, Verilator 5, Yosys, SymbiYosys with Yices,
`riscv64-unknown-elf-gcc` and Python 3 with `cocotb >= 2.0`. CI runs all of
it on every push.

## Repository layout

```
rtl/        riscv_core.sv (single-cycle), riscv_pipeline.sv (5-stage),
            riscv_decoder.sv, riscv_alu.sv, riscv_imm_gen.sv, riscv_regfile.sv,
            riscv_lsu.sv, rv32i_defs.svh
tb/         iss.py (reference ISS), rvgen.py (random programs),
            test_random.py (cocotb lockstep), tb_isa.sv, tb_rvfi.sv, sim_mem.sv
tests/      run_isa_tests.py, env/ (minimal test environment), riscv-tests/
formal/     riscv-formal wrapper and configurations, run.sh, riscv-formal/
fpga/       Nexys A7 top level, constraints, demo image, testbench
sw/         demo program and linker script
docs/       DESIGN.md
```

## Changes from v1

The first version supported only part of RV32I and was tested with one
five-instruction program:
- Every branch behaved as BEQ.
- I-type ALU instructions other than ADDI silently executed as ADDI.
- XOR, shifts, SLT/SLTU, LUI, AUIPC, JAL, JALR, and byte/halfword
  loads and stores were missing.
- Undefined instructions were not detected.

All of these are now implemented and verified, and the pipelined core is new.
