from riscvmodel.insn import InstructionMUL



class InstructionCZERO_EQZ:
    def __init__(self, rd, rs1, rs2):
        self.rd = rd
        self.rs1 = rs1
        self.rs2 = rs2
        self.op = 5

    def encode(self):
        return (0b0000111 << 25) | (self.rs2 << 20) | (self.rs1 << 15) | (self.op << 12) | (self.rd << 7) | 0b0110011

class InstructionCZERO_NEZ:
    def __init__(self, rd, rs1, rs2):
        self.rd = rd
        self.rs1 = rs1
        self.rs2 = rs2
        self.op = 7

    def encode(self):
        return (0b0000111 << 25) | (self.rs2 << 20) | (self.rs1 << 15) | (self.op << 12) | (self.rd << 7) | 0b0110011

