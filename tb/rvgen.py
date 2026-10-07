"""Constrained-random RV32I program generator.

Programs always terminate: control flow only moves forward (branches, JAL
and JALR targets are ahead of the current instruction and inside the
program), and every program ends in ECALL. Loads and stores go through x31,
which the prologue points at the data region. Register values are
randomised first so arithmetic starts from interesting operands.

The generated words are plain integers; the ISS and the RTL both execute
them from the same memory image.
"""

import random

DATA_BASE = 0x4000          # x31 points here; code lives below 0x3800

# --- encoders ----------------------------------------------------------------

def r_type(f7, rs2, rs1, f3, rd, op=0x33):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def i_type(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def s_type(imm, rs2, rs1, f3):
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) \
        | ((imm & 0x1F) << 7) | 0x23


def b_type(imm, rs2, rs1, f3):
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) \
        | (rs1 << 15) | (f3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63


def u_type(imm20, rd, op):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op


def j_type(imm, rd):
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) \
        | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


ECALL = 0x00000073
FENCE = 0x0FF0000F

R_OPS = [(0x00, 0), (0x20, 0), (0x00, 1), (0x00, 2), (0x00, 3),
         (0x00, 4), (0x00, 5), (0x20, 5), (0x00, 6), (0x00, 7)]
I_ALU = [0, 2, 3, 4, 6, 7]
LOADS = [0, 1, 2, 4, 5]
STORES = [0, 1, 2]
BRANCHES = [0, 1, 4, 5, 6, 7]


def load_value(rng):
    """lui+addi pair that sets a register to a random 32-bit value."""
    v = rng.choice([rng.getrandbits(32), 0, 0xFFFFFFFF, 0x80000000, 0x7FFFFFFF,
                    rng.randint(0, 31), rng.getrandbits(32)])
    lo = v & 0xFFF
    hi = ((v + 0x800) >> 12) & 0xFFFFF
    return hi, lo


def generate(seed, length=400, trap_rate=0.0):
    """Return a list of instruction words. trap_rate > 0 occasionally emits a
    misaligned access, a misaligned jump or an illegal instruction."""
    rng = random.Random(seed)
    prog = []

    def reg(allow_zero=True):
        lo = 0 if allow_zero and rng.random() < 0.05 else 1
        return rng.randint(lo, 30)

    # prologue: random register contents, x31 = data base
    for r in range(1, 31):
        hi, lo = load_value(rng)
        prog.append(u_type(hi, r, 0x37))
        prog.append(i_type(lo, r, 0, r, 0x13))
    prog.append(u_type(DATA_BASE >> 12, 31, 0x37))

    # body: list of (kind, args); control-flow targets are fixed up afterwards
    body = []
    weights = {"r": 22, "i": 18, "shift": 8, "lui": 4, "auipc": 3, "load": 14,
               "store": 12, "branch": 12, "jal": 3, "jalr": 3, "fence": 1}
    kinds = list(weights)
    for _ in range(length):
        kind = rng.choices(kinds, [weights[k] for k in kinds])[0]
        if trap_rate and rng.random() < trap_rate:
            kind = rng.choice(["mis_load", "mis_store", "mis_jalr", "illegal"])
        body.append(kind)

    words = []          # (word or ('branch'|'jal', ...)) placeholders
    for kind in body:
        if kind == "r":
            f7, f3 = rng.choice(R_OPS)
            words.append(r_type(f7, rng.randint(0, 31), rng.randint(0, 31), f3, reg()))
        elif kind == "i":
            words.append(i_type(rng.randint(-2048, 2047), rng.randint(0, 31),
                                rng.choice(I_ALU), reg(), 0x13))
        elif kind == "shift":
            f3, f7 = rng.choice([(1, 0x00), (5, 0x00), (5, 0x20)])
            words.append(i_type((f7 << 5) | rng.randint(0, 31), rng.randint(0, 31), f3, reg(), 0x13))
        elif kind in ("lui", "auipc"):
            words.append(u_type(rng.getrandbits(20), reg(), 0x37 if kind == "lui" else 0x17))
        elif kind in ("load", "mis_load"):
            f3 = rng.choice(LOADS)
            size = 1 << (f3 & 3)
            off = rng.randint(-512, 511) * size
            if kind == "mis_load":
                f3 = rng.choice([1, 2, 5])
                off = rng.randint(-512, 511) * 4 + rng.choice([1, 3])
            words.append(i_type(off, 31, f3, reg(), 0x03))
        elif kind in ("store", "mis_store"):
            f3 = rng.choice(STORES)
            size = 1 << f3
            off = rng.randint(-256, 511) * size
            if kind == "mis_store":
                f3 = rng.choice([1, 2])
                off = rng.randint(0, 511) * 4 + rng.choice([1, 3])
            words.append(s_type(off, rng.randint(0, 31), 31, f3))
        elif kind == "branch":
            words.append(("branch", rng.choice(BRANCHES), rng.randint(0, 31), rng.randint(0, 31),
                          rng.randint(1, 12)))
        elif kind == "jal":
            words.append(("jal", reg(), rng.randint(1, 12)))
        elif kind in ("jalr", "mis_jalr"):
            t = reg(allow_zero=False)
            skip = rng.randint(2, 12)
            extra = 2 if kind == "mis_jalr" else rng.choice([0, 1])   # bit 0 is ignored by JALR
            words.append(u_type(0, t, 0x17))                           # auipc t, 0
            words.append(("jalr", reg(), t, skip, extra))
        elif kind == "fence":
            words.append(FENCE)
        elif kind == "illegal":
            words.append(rng.choice([0x00000000, 0xFFFFFFFF, 0x00001073,      # CSRRW
                                     0x0000100F,                              # FENCE.I
                                     r_type(0x01, 1, 2, 0, 3)]))              # MUL (no M ext)

    words.append(ECALL)
    last = len(words) - 1
    # A jump must never land on a JALR (that would skip the AUIPC that sets
    # its base register), so such targets are moved back onto the AUIPC.
    jalr_at = {i for i, w in enumerate(words) if isinstance(w, tuple) and w[0] == "jalr"}

    def target(i, skip):
        t = min(i + skip, last)
        return t - 1 if t in jalr_at else t

    for i, w in enumerate(words):
        if isinstance(w, tuple):
            if w[0] == "branch":
                _, f3, a, b, skip = w
                words[i] = b_type((target(i, skip) - i) * 4, b, a, f3)
            elif w[0] == "jal":
                _, rd, skip = w
                words[i] = j_type((target(i, skip) - i) * 4, rd)
            else:                                   # jalr relative to the auipc at i-1
                _, rd, t, skip, extra = w
                words[i] = i_type((target(i, skip) - (i - 1)) * 4 + extra, t, 0, rd, 0x67)
    return prog + words
