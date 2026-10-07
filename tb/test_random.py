"""Random-instruction lockstep test.

Each program from rvgen.py is loaded into memory and run on the core. Every
instruction the core retires (its RVFI record) is compared field by field
with the Python ISS in iss.py: PC, next PC, instruction, trap, destination
register and value, memory address, byte masks and store data.

    make                    single-cycle core, default seed
    make SEED=7 N=200       more programs
"""

import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge

import rvgen
from coverage import cov
from iss import RV32I

SEED = int(os.environ.get("SEED", "1"))
N_PROGRAMS = int(os.environ.get("N", "40"))
MEM_BYTES = 65536
DATA_LO, DATA_HI = 0x3800, 0x4800        # region reachable by generated loads/stores

BRANCH = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}
LOAD = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}
STORE = {0: "sb", 1: "sh", 2: "sw"}
OPIMM = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi", 1: "slli"}
OP = {(0, 0): "add", (0x20, 0): "sub", (0, 1): "sll", (0, 2): "slt", (0, 3): "sltu",
      (0, 4): "xor", (0, 5): "srl", (0x20, 5): "sra", (0, 6): "or", (0, 7): "and"}
ALL = (["lui", "auipc", "jal", "jalr", "fence", "ecall"] + list(BRANCH.values()) + list(LOAD.values())
       + list(STORE.values()) + list(OPIMM.values()) + ["srli", "srai"] + list(OP.values()))

for m in ALL:
    cov.define(f"insn_{m}")
for b in BRANCH.values():
    cov.define(f"{b}_taken")
    cov.define(f"{b}_not_taken")
for off in range(4):
    cov.define(f"lb_lane{off}")
    cov.define(f"sb_lane{off}")
for off in (0, 2):
    cov.define(f"lh_lane{off}")
    cov.define(f"sh_lane{off}")
for name in ("write_to_x0", "jalr_bit0_ignored", "trap_illegal", "trap_misaligned_load",
             "trap_misaligned_store", "trap_misaligned_jump"):
    cov.define(name)


def mnemonic(insn):
    op, f3, f7 = insn & 0x7F, (insn >> 12) & 7, insn >> 25
    if op == 0x37: return "lui"
    if op == 0x17: return "auipc"
    if op == 0x6F: return "jal"
    if op == 0x67: return "jalr"
    if op == 0x63: return BRANCH.get(f3)
    if op == 0x03: return LOAD.get(f3)
    if op == 0x23: return STORE.get(f3)
    if op == 0x13:
        if f3 == 5: return "srai" if f7 == 0x20 else "srli"
        return OPIMM.get(f3)
    if op == 0x33: return OP.get((f7, f3))
    if op == 0x0F: return "fence"
    if insn == 0x73: return "ecall"
    return None


def uint(h):
    return int(str(h.value), 2)


def bits(h):
    """Signal value as a bit string, MSB first; may contain X/Z."""
    return str(h.value).lower()


def as_int(b, what, where):
    assert not set(b) & set("xz"), f"{where}: {what} is undefined ({b})"
    return int(b, 2)


def read_rvfi(dut):
    """Raw bit strings: fields that do not matter for an instruction (for
    example store data on an ALU instruction) may legitimately be X."""
    return {k: bits(getattr(dut, f"rvfi_{k}")) for k in (
        "insn", "trap", "rd_addr", "rd_wdata", "pc_rdata", "pc_wdata",
        "mem_addr", "mem_rmask", "mem_wmask", "mem_wdata")}


def compare(raw, exp, where):
    for k in ("pc_rdata", "insn", "trap", "rd_addr", "rd_wdata", "mem_rmask", "mem_wmask"):
        got = as_int(raw[k], k, where)
        assert got == int(exp[k]), f"{where}: {k} = {got:#x}, ISS says {int(exp[k]):#x}"
    if not exp["trap"]:
        got = as_int(raw["pc_wdata"], "pc_wdata", where)
        assert got == exp["pc_wdata"], f"{where}: next pc = {got:#x}, ISS says {exp['pc_wdata']:#x}"
    if exp["mem_rmask"] or exp["mem_wmask"]:
        got = as_int(raw["mem_addr"], "mem_addr", where)
        assert got == exp["mem_addr"], f"{where}: mem_addr = {got:#x}, ISS says {exp['mem_addr']:#x}"
    for lane in range(4):
        if exp["mem_wmask"] >> lane & 1:
            g = as_int(raw["mem_wdata"][24 - 8 * lane:32 - 8 * lane], f"store byte {lane}", where)
            e = (exp["mem_wdata"] >> 8 * lane) & 0xFF
            assert g == e, f"{where}: store byte {lane} = {g:#x}, ISS says {e:#x}"


def record_coverage(rec):
    insn = rec["insn"]
    m = mnemonic(insn)
    if rec["trap"]:
        if m is None:
            cov.hit("trap_illegal")
        elif m in LOAD.values():
            cov.hit("trap_misaligned_load")
        elif m in STORE.values():
            cov.hit("trap_misaligned_store")
        elif m in ("jal", "jalr") or m in BRANCH.values():
            cov.hit("trap_misaligned_jump")
        elif m == "ecall":
            cov.hit("insn_ecall")
        return
    cov.hit(f"insn_{m}")
    if m in BRANCH.values():
        taken = rec["pc_wdata"] != (rec["pc_rdata"] + 4) & 0xFFFFFFFF
        cov.hit(f"{m}_{'taken' if taken else 'not_taken'}")
    lane = (rec["mem_rmask"] | rec["mem_wmask"]).bit_length() - 1 if (rec["mem_rmask"] | rec["mem_wmask"]) else 0
    if m in ("lb", "lbu"):
        cov.hit(f"lb_lane{lane}")
    if m == "sb":
        cov.hit(f"sb_lane{lane}")
    if m in ("lh", "lhu"):
        cov.hit(f"lh_lane{lane - 1}")
    if m == "sh":
        cov.hit(f"sh_lane{lane - 1}")
    writes_rd = m not in BRANCH.values() and m not in STORE.values() and m != "fence"
    if writes_rd and (insn >> 7) & 0x1F == 0:
        cov.hit("write_to_x0")
    if m == "jalr" and (insn >> 20) & 1:
        cov.hit("jalr_bit0_ignored")


async def run_program(dut, words, rng, max_cycles=20000):
    await FallingEdge(dut.clk)
    dut.rst_n.value = 0
    image = bytearray(MEM_BYTES)
    for i, w in enumerate(words):
        image[4 * i:4 * i + 4] = w.to_bytes(4, "little")
    image[DATA_LO:DATA_HI] = bytes(rng.getrandbits(8) for _ in range(DATA_HI - DATA_LO))
    mem = dut.u_mem.mem
    for i in list(range(len(words))) + list(range(DATA_LO // 4, DATA_HI // 4)):
        mem[i].value = int.from_bytes(image[4 * i:4 * i + 4], "little")
    iss = RV32I(bytearray(image))

    await ClockCycles(dut.clk, 2, rising=False)
    dut.rst_n.value = 1

    retired = 0
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if bit := uint(dut.rvfi_valid):
            got = read_rvfi(dut)
            exp = iss.step()
            compare(got, exp, f"instruction {retired} at pc {exp['pc_rdata']:#06x}")
            record_coverage(exp)
            retired += bit
            if exp["trap"]:
                break
    else:
        raise AssertionError("program did not finish")

    # once trapped, the core must stay halted and retire nothing more
    for _ in range(3):
        await RisingEdge(dut.clk)
        await ReadOnly()
        assert uint(dut.halted) == 1 and uint(dut.rvfi_valid) == 0
    return retired


@cocotb.test()
async def test_random_programs(dut):
    """Random programs that run to their final ECALL."""
    Clock(dut.clk, 10, unit="ns").start()
    total = 0
    for p in range(N_PROGRAMS):
        rng = random.Random(SEED * 1000 + p)
        total += await run_program(dut, rvgen.generate(SEED * 1000 + p, length=400), rng)
    dut._log.info("%d programs, %d instructions checked against the ISS", N_PROGRAMS, total)


@cocotb.test()
async def test_random_traps(dut):
    """Programs with misaligned accesses/jumps and illegal instructions mixed in:
    the core must stop at exactly the same instruction as the ISS."""
    Clock(dut.clk, 10, unit="ns").start()
    for p in range(N_PROGRAMS):
        rng = random.Random(SEED * 2000 + p)
        await run_program(dut, rvgen.generate(SEED * 2000 + p, length=300, trap_rate=0.01), rng)


@cocotb.test()
async def test_coverage_closure(dut):
    """Fails if any coverage bin was never hit."""
    dut._log.info("\n%s", cov.report())
    with open(os.environ.get("COVERAGE_REPORT", "coverage_random.txt"), "w") as f:
        f.write(cov.report() + "\n")
    assert not cov.missing(), f"uncovered bins: {cov.missing()}"
