#!/usr/bin/env python3
"""Build and run the official riscv-tests RV32UI suite on the core.

    python3 tests/run_isa_tests.py                 # all tests, single-cycle core
    python3 tests/run_isa_tests.py add beq lw      # a subset
    python3 tests/run_isa_tests.py --core <module> --gp <hier.path>

Each test is assembled with riscv64-unknown-elf-gcc against the minimal
environment in tests/env, converted to a hex image and run on tb/tb_isa.sv
under Icarus Verilog. Exit status is non-zero if any test does not pass.
"""
import argparse
import concurrent.futures as cf
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "tests"
SUITE = TESTS / "riscv-tests" / "isa"
BUILD = ROOT / "build" / "isa"
PREFIX = "riscv64-unknown-elf-"

# rv32ui tests from riscv-tests/isa/rv32ui/Makefrag, minus two that need
# features this core deliberately lacks:
#   fence_i  self-modifying code + Zifencei
#   ma_data  misaligned loads/stores (this core traps on them, as allowed)
RV32UI = """
simple add addi and andi auipc beq bge bgeu blt bltu bne jal jalr
lb lbu lh lhu lw ld_st lui or ori sb sh sw st_ld sll slli
slt slti sltiu sltu sra srai srl srli sub xor xori
""".split()

CORE_SOURCES = ["riscv_decoder.sv", "riscv_imm_gen.sv", "riscv_alu.sv",
                "riscv_regfile.sv", "riscv_lsu.sv", "riscv_core.sv"]


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


def build_test(name):
    BUILD.mkdir(parents=True, exist_ok=True)
    elf = BUILD / f"{name}.elf"
    binf = BUILD / f"{name}.bin"
    hexf = BUILD / f"{name}.hex"
    run([f"{PREFIX}gcc", "-march=rv32i", "-mabi=ilp32", "-static", "-nostdlib",
         "-nostartfiles", "-T", str(TESTS / "env" / "link.ld"),
         "-I", str(TESTS / "env"), "-I", str(SUITE / "macros" / "scalar"),
         str(SUITE / "rv32ui" / f"{name}.S"), "-o", str(elf)])
    run([f"{PREFIX}objcopy", "-O", "binary", str(elf), str(binf)])
    data = binf.read_bytes()
    data += bytes(-len(data) % 4)
    words = [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]
    hexf.write_text("\n".join(f"{w:08x}" for w in words) + "\n")
    return hexf


def compile_tb(core, gp, sources):
    sim = BUILD / f"tb_{core}.vvp"
    BUILD.mkdir(parents=True, exist_ok=True)
    run(["iverilog", "-g2012", "-I", str(ROOT / "rtl"), f"-DCORE={core}", f"-DGP_REG={gp}",
         "-o", str(sim), str(ROOT / "tb" / "sim_mem.sv"), str(ROOT / "tb" / "tb_isa.sv"),
         *[str(ROOT / "rtl" / s) for s in sources]])
    return sim


def run_test(sim, name):
    hexf = build_test(name)
    out = run(["vvp", "-n", str(sim), f"+hex={hexf}"]).stdout
    line = next((l for l in out.splitlines() if l.startswith("RESULT")), "RESULT NO-OUTPUT")
    return name, line[len("RESULT "):]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tests", nargs="*", default=RV32UI)
    ap.add_argument("--core", default="riscv_core")
    ap.add_argument("--gp", default="u_rf.regs[3]")
    ap.add_argument("--sources", nargs="*", default=CORE_SOURCES)
    args = ap.parse_args()

    sim = compile_tb(args.core, args.gp, args.sources)
    with cf.ThreadPoolExecutor() as pool:
        results = list(pool.map(lambda t: run_test(sim, t), args.tests))

    failed = [r for r in results if not r[1].startswith("PASS")]
    for name, res in results:
        print(f"  {name:<8} {res}")
    print(f"{len(results) - len(failed)}/{len(results)} riscv-tests passed on {args.core}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
