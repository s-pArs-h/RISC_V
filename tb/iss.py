"""Reference RV32I instruction-set simulator.

Written straight from the ISA manual, independent of the RTL. step() executes
one instruction and returns the same fields the core reports on its RVFI
trace port, so the two can be compared instruction by instruction.

Trap behaviour matches the core's documented behaviour: illegal
instructions, ECALL/EBREAK, misaligned loads/stores and misaligned jump or
branch targets stop execution without changing any state.
"""

MASK = 0xFFFFFFFF


def sext(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value >> (bits - 1) else value


def signed(v):
    return sext(v, 32)


class RV32I:
    def __init__(self, mem, pc=0):
        self.mem = mem              # bytearray, addresses wrap at its size
        self.x = [0] * 32
        self.pc = pc
        self.halted = False

    # -- memory -------------------------------------------------------------
    def _word_addr(self, addr):
        return (addr & ~3) % len(self.mem)

    def read_word(self, addr):
        a = self._word_addr(addr)
        return int.from_bytes(self.mem[a:a + 4], "little")

    def write_lanes(self, addr, mask, data):
        a = self._word_addr(addr)
        for lane in range(4):
            if mask >> lane & 1:
                self.mem[a + lane] = (data >> (8 * lane)) & 0xFF

    # -- execution ----------------------------------------------------------
    def step(self):
        pc = self.pc
        insn = self.read_word(pc)
        rec = dict(pc_rdata=pc, insn=insn, trap=False, rd_addr=0, rd_wdata=0,
                   pc_wdata=(pc + 4) & MASK, mem_addr=0, mem_rmask=0,
                   mem_wmask=0, mem_wdata=0)

        opcode = insn & 0x7F
        rd = (insn >> 7) & 0x1F
        f3 = (insn >> 12) & 0x7
        rs1 = (insn >> 15) & 0x1F
        rs2 = (insn >> 20) & 0x1F
        f7 = insn >> 25
        a, b = self.x[rs1], self.x[rs2]
        imm_i = sext(insn >> 20, 12)
        imm_s = sext(((insn >> 25) << 5) | ((insn >> 7) & 0x1F), 12)
        imm_b = sext((((insn >> 31) & 1) << 12) | (((insn >> 7) & 1) << 11)
                     | (((insn >> 25) & 0x3F) << 5) | (((insn >> 8) & 0xF) << 1), 13)
        imm_u = insn & 0xFFFFF000
        imm_j = sext((((insn >> 31) & 1) << 20) | (((insn >> 12) & 0xFF) << 12)
                     | (((insn >> 20) & 1) << 11) | (((insn >> 21) & 0x3FF) << 1), 21)

        result = None           # value for rd, if the instruction writes one
        next_pc = (pc + 4) & MASK
        trap = False

        if opcode == 0x37:                                    # LUI
            result = imm_u
        elif opcode == 0x17:                                  # AUIPC
            result = (pc + imm_u) & MASK
        elif opcode == 0x6F:                                  # JAL
            result = (pc + 4) & MASK
            next_pc = (pc + imm_j) & MASK
            trap = next_pc & 3 != 0
        elif opcode == 0x67 and f3 == 0:                      # JALR
            result = (pc + 4) & MASK
            next_pc = (a + imm_i) & MASK & ~1
            trap = next_pc & 3 != 0
        elif opcode == 0x63 and f3 not in (2, 3):             # branches
            taken = {0: a == b, 1: a != b,
                     4: signed(a) < signed(b), 5: signed(a) >= signed(b),
                     6: a < b, 7: a >= b}[f3]
            if taken:
                next_pc = (pc + imm_b) & MASK
                trap = next_pc & 3 != 0
        elif opcode == 0x03 and f3 in (0, 1, 2, 4, 5):        # loads
            addr = (a + imm_i) & MASK
            size = 1 << (f3 & 3)
            off = addr & 3
            if addr % size:
                trap = True
            else:
                word = self.read_word(addr)
                lane = (word >> (8 * off)) & ((1 << (8 * size)) - 1)
                result = lane if f3 & 4 or size == 4 else sext(lane, 8 * size) & MASK
                rec.update(mem_addr=addr & ~3, mem_rmask=((1 << size) - 1) << off)
        elif opcode == 0x23 and f3 in (0, 1, 2):              # stores
            addr = (a + imm_s) & MASK
            size = 1 << f3
            off = addr & 3
            if addr % size:
                trap = True
            else:
                mask = ((1 << size) - 1) << off
                data = (b << (8 * off)) & MASK
                self.write_lanes(addr, mask, data)
                rec.update(mem_addr=addr & ~3, mem_wmask=mask, mem_wdata=data)
        elif opcode == 0x13:                                  # OP-IMM
            shamt = (insn >> 20) & 0x1F
            if f3 == 1:
                trap = f7 != 0
                result = (a << shamt) & MASK
            elif f3 == 5:
                trap = f7 not in (0x00, 0x20)
                result = (signed(a) >> shamt) & MASK if f7 == 0x20 else a >> shamt
            else:
                result = {0: (a + imm_i) & MASK, 2: int(signed(a) < imm_i),
                          3: int(a < (imm_i & MASK)), 4: (a ^ imm_i) & MASK,
                          6: (a | imm_i) & MASK, 7: (a & imm_i) & MASK}[f3]
        elif opcode == 0x33:                                  # OP
            ops = {
                (0x00, 0): lambda: (a + b) & MASK,
                (0x20, 0): lambda: (a - b) & MASK,
                (0x00, 1): lambda: (a << (b & 31)) & MASK,
                (0x00, 2): lambda: int(signed(a) < signed(b)),
                (0x00, 3): lambda: int(a < b),
                (0x00, 4): lambda: a ^ b,
                (0x00, 5): lambda: a >> (b & 31),
                (0x20, 5): lambda: (signed(a) >> (b & 31)) & MASK,
                (0x00, 6): lambda: a | b,
                (0x00, 7): lambda: a & b,
            }
            if (f7, f3) in ops:
                result = ops[(f7, f3)]()
            else:
                trap = True
        elif opcode == 0x0F and f3 == 0:                      # FENCE: no-op
            pass
        else:                                                 # ECALL, EBREAK, illegal
            trap = True

        if trap:
            # nothing architectural changes; a store has not happened yet
            rec.update(trap=True, pc_wdata=pc, mem_addr=0, mem_rmask=0, mem_wmask=0, mem_wdata=0)
            self.halted = True
            return rec

        if result is not None:
            rec["rd_addr"] = rd
            if rd:
                self.x[rd] = result & MASK
                rec["rd_wdata"] = result & MASK
        rec["pc_wdata"] = next_pc
        self.pc = next_pc
        return rec
