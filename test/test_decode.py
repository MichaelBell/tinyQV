import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

from riscvmodel.insn import *
from core_instr import *

@cocotb.test()
async def test_load(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    ops = [
        (InstructionLW, 0b010),
        (InstructionLH, 0b001),
        (InstructionLB, 0b000),
        (InstructionLBU, 0b100),
        (InstructionLHU, 0b101),
    ]

    for i in range(400):
        reg = random.randint(0, 15)
        base_reg = random.randint(0, 15)
        offset = random.randint(-2048, 2047)
        op = random.choice(ops)
        dut.instr.value = op[0](reg, base_reg, offset).encode()
        await Timer(1, "ns")

        assert dut.is_load.value == 1
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 4

        assert dut.imm.value.signed_integer == offset
        assert dut.alu_op.value == 0  # ADD
        assert dut.mem_op.value == op[1]
        
        assert dut.rs1.value == base_reg
        assert dut.rd.value == reg

        assert dut.additional_mem_ops.value == 0

    def encode_clw(reg, base_reg, imm):
        scrambled = (((imm << (10 - 3)) & 0b1110000000000) |
                     ((imm << ( 6 - 2)) & 0b0000001000000) |
                     ((imm >> ( 6 - 5)) & 0b0000000100000))
        return 0x4000 | scrambled | ((base_reg - 8) << 7) | ((reg - 8) << 2)        

    for i in range(100):
        reg = random.randint(8, 15)
        base_reg = random.randint(8, 15)
        offset = random.randint(0, 31) * 4
        dut.instr.value = encode_clw(reg, base_reg, offset)
        await Timer(1, "ns")

        assert dut.is_load.value == 1
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value.signed_integer == offset
        assert dut.alu_op.value == 0  # ADD
        assert dut.mem_op.value == 0b010
        
        assert dut.rs1.value == base_reg
        assert dut.rd.value == reg

    def encode_clwsp(reg, base_reg, imm):
        scrambled = (((imm << (12 - 5)) & 0b1000000000000) |
                     ((imm << ( 4 - 2)) & 0b0000001110000) |
                     ((imm >> ( 6 - 2)) & 0b0000000001100))
        if base_reg == 2:
            return 0x4002 | scrambled | (reg << 7)
        else:
            return 0x6002 | scrambled | (reg << 7)

    for i in range(100):
        reg = random.randint(1, 15)
        base_reg = random.choice((2, 4))
        offset = random.randint(0, 63) * 4
        dut.instr.value = encode_clwsp(reg, base_reg, offset)
        await Timer(1, "ns")

        assert dut.is_load.value == 1
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value.signed_integer == offset
        assert dut.alu_op.value == 0  # ADD
        assert dut.mem_op.value == 0b010
        
        assert dut.rs1.value == base_reg
        assert dut.rd.value == reg

    def encode_lw2(reg, base_reg, imm):
        instr = InstructionLW(reg, base_reg, imm).encode()
        return instr | (1 << 12)

    def encode_lw4(reg, base_reg, imm):
        instr = InstructionLW(reg, base_reg, imm).encode()
        return instr | (7 << 12)

    ops = [
        (encode_lw2, 1),
        (encode_lw4, 3)
    ]

    for i in range(100):
        reg = random.randint(0, 15)
        base_reg = random.randint(0, 15)
        offset = random.randint(-2048, 2047)
        op = random.choice(ops)
        dut.instr.value = op[0](reg, base_reg, offset)
        await Timer(1, "ns")

        assert dut.is_load.value == 1
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 4

        assert dut.imm.value.signed_integer == offset
        assert dut.alu_op.value == 0  # ADD
        assert dut.mem_op.value == 2
        
        assert dut.rs1.value == base_reg
        assert dut.rd.value == reg

        assert dut.additional_mem_ops.value == op[1]
        assert dut.mem_op_increment_reg == 1


    def encode_lh(reg, base_reg, imm):
        scrambled = ((imm << (5 - 1)) & 0b100000)
        return 0x8440 | scrambled | ((base_reg - 8) << 7) | ((reg - 8) << 2)

    def encode_lhu(reg, base_reg, imm):
        scrambled = ((imm << (5 - 1)) & 0b100000)
        return 0x8400 | scrambled | ((base_reg - 8) << 7) | ((reg - 8) << 2)

    def encode_lbu(reg, base_reg, imm):
        scrambled = (((imm << (5 - 1)) & 0b0100000) |
                     ((imm << (6 - 0)) & 0b1000000))
        return 0x8000 | scrambled | ((base_reg - 8) << 7) | ((reg - 8) << 2)

    ops = [
        (encode_lh, 0b001),
        (encode_lhu, 0b101),
        (encode_lbu, 0b100),
    ]

    for i in range(200):
        reg = random.randint(8, 15)
        base_reg = random.randint(8, 15)
        offset = random.randint(0, 1) * 2
        op = random.choice(ops)
        if (op[1] & 3) == 0:
            offset += random.randint(0, 1)
        dut.instr.value = op[0](reg, base_reg, offset)
        await Timer(1, "ns")

        assert dut.is_load.value == 1
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value.signed_integer == offset
        assert dut.alu_op.value == 0  # ADD
        assert dut.mem_op.value == op[1]
        
        assert dut.rs1.value == base_reg
        assert dut.rd.value == reg

        assert dut.additional_mem_ops.value == 0

@cocotb.test()
async def test_alu_imm(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    ops = [
        (InstructionADDI, 0b0000, True),
        (InstructionANDI, 0b0111, True),
        (InstructionORI,  0b0110, True),
        (InstructionXORI, 0b0100, True),
        (InstructionSLTI, 0b0010, True),
        (InstructionSLTIU,0b0011, True),
        (InstructionSLLI, 0b0001, False),
        (InstructionSRLI, 0b0101, False),
        (InstructionSRAI, 0b1101, False),
    ]

    for i in range(800):
        src_reg = random.randint(0, 15)
        dest_reg = random.randint(0, 15)
        op = random.choice(ops)
        if op[2]: imm = random.randint(-2048, 2047)
        else: imm = random.randint(0, 31)

        dut.instr.value = op[0](dest_reg, src_reg, imm).encode()
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 1
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 4

        if op[2]: assert dut.imm.value.signed_integer == imm
        else: assert dut.imm.value & 0x1F == imm
        assert dut.alu_op.value == op[1]

        assert dut.rs1.value == src_reg
        assert dut.rd.value == dest_reg

    def encode_ci(reg, imm, opcode):
        scrambled = (((imm << (12 - 5)) & 0b1000000000000) |
                     ((imm << ( 2 - 0)) & 0b0000001111100))
        return opcode | scrambled | (reg << 7)
    
    def encode_cli(reg, imm):
        return encode_ci(reg, imm, 0x4001)

    def encode_caddi(reg, imm):
        return encode_ci(reg, imm, 0x0001)

    def encode_cslli(reg, imm):
        return encode_ci(reg, imm, 0x0002)

    for i in range(100):
        dest_reg = random.randint(1, 15)
        imm = random.randint(0, 31)

        dut.instr.value = encode_cli(dest_reg, imm)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 1
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value.signed_integer == imm
        assert dut.alu_op.value == 0

        assert dut.rs1.value == 0
        assert dut.rd.value == dest_reg        

    ops = [
        (encode_caddi, 0b0000, True),
        (encode_cslli, 0b0001, False),
    ]

    for i in range(200):
        dest_reg = random.randint(0, 15)
        op = random.choice(ops)
        imm = random.randint(0, 31)

        dut.instr.value = op[0](dest_reg, imm)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 1
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        if op[2]: assert dut.imm.value.signed_integer == imm
        else: assert dut.imm.value & 0x1F == imm
        assert dut.alu_op.value == op[1]

        assert dut.rs1.value == dest_reg
        assert dut.rd.value == dest_reg

    def encode_ci2(reg, imm, opcode):
        return encode_ci(reg - 8, imm, opcode)
    
    def encode_csrli(reg, imm):
        return encode_ci2(reg, imm, 0x8001)

    def encode_csrai(reg, imm):
        return encode_ci2(reg, imm, 0x8401)

    def encode_candi(reg, imm):
        return encode_ci2(reg, imm, 0x8801)

    ops = [
        (encode_csrli, 0b0101, False),
        (encode_csrai, 0b1101, False),
        (encode_candi, 0b0111, True),
    ]

    for i in range(300):
        dest_reg = random.randint(8, 15)
        op = random.choice(ops)
        imm = random.randint(0, 31)

        dut.instr.value = op[0](dest_reg, imm)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 1
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        if op[2]: assert dut.imm.value.signed_integer == imm
        else: assert dut.imm.value & 0x1F == imm
        assert dut.alu_op.value == op[1]

        assert dut.rs1.value == dest_reg
        assert dut.rd.value == dest_reg

    def encode_caddi4spn(reg, imm):
        scrambled = (((imm << (11 - 4)) & 0b1100000000000) |
                     ((imm << ( 7 - 6)) & 0b0011110000000) |
                     ((imm << ( 6 - 2)) & 0b0000001000000) |
                     ((imm << ( 5 - 3)) & 0b0000000100000))
        return 0x0000 | scrambled | ((reg - 8) << 2)
    
    for i in range(100):
        reg = random.randint(8, 15)
        imm = random.randint(0, 255) * 4

        dut.instr.value = encode_caddi4spn(reg, imm)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 1
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value.signed_integer == imm
        assert dut.alu_op.value == 0

        assert dut.rs1.value == 2
        assert dut.rd.value == reg  
    
    def encode_caddi16sp(imm):
        scrambled = (((imm << (12 - 9)) & 0b1000000000000) |
                     ((imm << ( 6 - 4)) & 0b0000001000000) |
                     ((imm >> ( 6 - 5)) & 0b0000000100000) |
                     ((imm >> ( 7 - 3)) & 0b0000000011000) |
                     ((imm >> ( 5 - 2)) & 0b0000000000100))
        return 0x6101 | scrambled
    
    for i in range(100):
        imm = random.randint(-32, 31) * 16

        dut.instr.value = encode_caddi16sp(imm)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 1
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value.signed_integer == imm
        assert dut.alu_op.value == 0

        assert dut.rs1.value == 2
        assert dut.rd.value == 2

    def encode_cnot(reg):
        return 0x9c75 | ((reg - 8) << 7)

    def encode_czext_b(reg):
        return 0x9c61 | ((reg - 8) << 7)

    def encode_czext_h(reg):
        return 0x9c69 | ((reg - 8) << 7)

    ops = [
        (encode_cnot, 0b0100, 0xFFFFFFFF),
        (encode_czext_b, 0b0111, 0xFF),
        (encode_czext_h, 0b0111, 0xFFFF),
    ]

    for i in range(200):
        dest_reg = random.randint(8, 15)
        op = random.choice(ops)
        imm = random.randint(0, 31)

        dut.instr.value = op[0](dest_reg)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 1
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value == op[2]
        assert dut.alu_op.value == op[1]

        assert dut.rs1.value == dest_reg
        assert dut.rd.value == dest_reg


@cocotb.test()
async def test_alu_reg(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    ops = [
        (InstructionADD, 0b0000, True),
        (InstructionSUB, 0b1000, True),
        (InstructionAND, 0b0111, True),
        (InstructionOR,  0b0110, True),
        (InstructionXOR, 0b0100, True),
        (InstructionSLT, 0b0010, True),
        (InstructionSLTU,0b0011, True),
        (InstructionSLL, 0b0001, False),
        (InstructionSRL, 0b0101, False),
        (InstructionSRA, 0b1101, False),
        (InstructionMUL16, 0b1010, False),
        (InstructionCZERO_EQZ, 0b1110, False),
        (InstructionCZERO_NEZ, 0b1111, False),
    ]

    for i in range(800):
        src_reg = random.randint(0, 15)
        src_reg2 = random.randint(0, 15)
        dest_reg = random.randint(0, 15)
        op = random.choice(ops)

        dut.instr.value = op[0](dest_reg, src_reg, src_reg2).encode()
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 1
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 4

        assert dut.alu_op.value == op[1]

        assert dut.rs1.value == src_reg
        assert dut.rs2.value == src_reg2
        assert dut.rd.value == dest_reg

    def encode_cr(dest_reg, src_reg, opcode):
        return opcode | (dest_reg << 7) | (src_reg << 2)
    
    def encode_cmv(dest_reg, src_reg):
        return encode_cr(dest_reg, src_reg, 0x8002)

    def encode_cadd(dest_reg, src_reg):
        return encode_cr(dest_reg, src_reg, 0x9002)

    for i in range(200):
        src_reg = random.randint(1, 15)
        dest_reg = random.randint(1, 15)
        move = random.choice((True, False))

        if move:
            dut.instr.value = encode_cmv(dest_reg, src_reg)
        else:
            dut.instr.value = encode_cadd(dest_reg, src_reg)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 1
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.alu_op.value == 0

        assert dut.rs1.value == (0 if move else dest_reg)
        assert dut.rs2.value == src_reg
        assert dut.rd.value == dest_reg

    def encode_cmul16(dest_reg, src_reg):
        return encode_cr(dest_reg, src_reg, 0xA002)
    
    for i in range(100):
        src_reg = random.randint(1, 15)
        dest_reg = random.randint(1, 15)

        dut.instr.value = encode_cmul16(dest_reg, src_reg)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 1
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.alu_op.value == 0b1010

        assert dut.rs1.value == dest_reg
        assert dut.rs2.value == src_reg
        assert dut.rd.value == dest_reg

    def encode_ca(dest_reg, src_reg, opcode):
        return opcode | ((dest_reg - 8) << 7) | ((src_reg - 8) << 2)
    
    def encode_csub(dest_reg, src_reg):
        return encode_ca(dest_reg, src_reg, 0x8C01)

    def encode_cxor(dest_reg, src_reg):
        return encode_ca(dest_reg, src_reg, 0x8C21)

    def encode_cor(dest_reg, src_reg):
        return encode_ca(dest_reg, src_reg, 0x8C41)

    def encode_cand(dest_reg, src_reg):
        return encode_ca(dest_reg, src_reg, 0x8C61)

    ops = [
        (encode_csub, 0b1000, True),
        (encode_cand, 0b0111, True),
        (encode_cor,  0b0110, True),
        (encode_cxor, 0b0100, True),
    ]

    for i in range(400):
        src_reg = random.randint(8, 15)
        dest_reg = random.randint(8, 15)
        op = random.choice(ops)

        dut.instr.value = op[0](dest_reg, src_reg)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 1
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.alu_op.value == op[1]

        assert dut.rs1.value == dest_reg
        assert dut.rs2.value == src_reg
        assert dut.rd.value == dest_reg

@cocotb.test()
async def test_auipc(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    for i in range(100):
        reg = random.randint(0, 15)
        offset = random.randint(0, 0xFFFFF)
        dut.instr.value = InstructionAUIPC(reg, offset).encode()
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 1
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 4

        assert dut.imm.value == offset << 12
        assert dut.alu_op.value == 0  # ADD
        
        assert dut.rd.value == reg

@cocotb.test()
async def test_store(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    ops = [
        (InstructionSW, 0b010),
        (InstructionSH, 0b001),
        (InstructionSB, 0b000),
    ]

    for i in range(200):
        reg = random.randint(0, 15)
        base_reg = random.randint(0, 15)
        offset = random.randint(-2048, 2047)
        op = random.choice(ops)
        dut.instr.value = op[0](base_reg, reg, offset).encode()
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 1
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 4

        assert dut.imm.value.signed_integer == offset
        assert dut.alu_op.value == 0  # ADD
        assert dut.mem_op.value == op[1]
        
        assert dut.rs1.value == base_reg
        assert dut.rs2.value == reg

    def encode_csw(base_reg, reg, imm):
        scrambled = (((imm << (10 - 3)) & 0b1110000000000) |
                     ((imm << ( 6 - 2)) & 0b0000001000000) |
                     ((imm >> ( 6 - 5)) & 0b0000000100000))
        return 0xC000 | scrambled | ((base_reg - 8) << 7) | ((reg - 8) << 2)

    for i in range(100):
        reg = random.randint(8, 15)
        base_reg = random.randint(8, 15)
        offset = random.randint(0, 31) * 4
        dut.instr.value = encode_csw(base_reg, reg, offset)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 1
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value.signed_integer == offset
        assert dut.alu_op.value == 0  # ADD
        assert dut.mem_op.value == 0b010
        
        assert dut.rs1.value == base_reg
        assert dut.rs2.value == reg

    def encode_cswsp(base_reg, reg, imm):
        scrambled = (((imm << ( 9 - 2)) & 0b1111000000000) |
                     ((imm << ( 7 - 6)) & 0b0000110000000))
        if base_reg == 2:
            return 0xC002 | scrambled | (reg << 2)
        else:
            return 0xE002 | scrambled | (reg << 2)

    for i in range(100):
        reg = random.randint(0, 15)
        base_reg = random.choice((2, 4))
        offset = random.randint(0, 63) * 4
        dut.instr.value = encode_cswsp(base_reg, reg, offset)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 1
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value.signed_integer == offset
        assert dut.alu_op.value == 0  # ADD
        assert dut.mem_op.value == 0b010
        
        assert dut.rs1.value == base_reg
        assert dut.rs2.value == reg

    def encode_sw2(base_reg, reg, imm):
        instr = InstructionSW(base_reg, reg, imm).encode()
        return instr | (1 << 12)

    def encode_sw4(base_reg, reg, imm):
        instr = InstructionSW(base_reg, reg, imm).encode()
        return instr | (7 << 12)

    def encode_sw4n(base_reg, reg, imm):
        instr = InstructionSW(base_reg, reg, imm).encode()
        return instr | (6 << 12)

    ops = [
        (encode_sw2, 1, 1),
        (encode_sw4, 3, 1),
        (encode_sw4n, 3, 0)
    ]

    for i in range(200):
        reg = random.randint(0, 15)
        base_reg = random.randint(0, 15)
        offset = random.randint(-2048, 2047)
        op = random.choice(ops)
        dut.instr.value = op[0](base_reg, reg, offset)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 1
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 4

        assert dut.imm.value.signed_integer == offset
        assert dut.alu_op.value == 0  # ADD
        assert dut.mem_op.value == 2
        
        assert dut.rs1.value == base_reg
        assert dut.rs2.value == reg

        assert dut.additional_mem_ops.value == op[1]
        assert dut.mem_op_increment_reg == op[2]

    def encode_sh(base_reg, reg, imm):
        scrambled = ((imm << (5 - 1)) & 0b100000)
        return 0x8c00 | scrambled | ((base_reg - 8) << 7) | ((reg - 8) << 2)

    def encode_sb(base_reg, reg, imm):
        scrambled = (((imm << (5 - 1)) & 0b0100000) |
                     ((imm << (6 - 0)) & 0b1000000))
        return 0x8800 | scrambled | ((base_reg - 8) << 7) | ((reg - 8) << 2)

    ops = [
        (encode_sh, 0b001),
        (encode_sb, 0b000),
    ]    

    for i in range(100):
        reg = random.randint(8, 15)
        base_reg = random.randint(8, 15)
        offset = random.randint(0, 1) * 2
        op = random.choice(ops)
        if (op[1] & 3) == 0:
            offset += random.randint(0, 1)
        dut.instr.value = op[0](base_reg, reg, offset)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 1
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value.signed_integer == offset
        assert dut.alu_op.value == 0  # ADD
        assert dut.mem_op.value == op[1]
        
        assert dut.rs1.value == base_reg
        assert dut.rs2.value == reg

@cocotb.test()
async def test_lui(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    for i in range(100):
        reg = random.randint(0, 15)
        imm = random.randint(0, 0xFFFFF)
        dut.instr.value = InstructionLUI(reg, imm).encode()
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 1
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 4

        assert dut.imm.value == imm << 12
        
        assert dut.rd.value == reg

    def encode_clui(reg, imm):
        scrambled = (((imm << (12 - 5)) & 0b1000000000000) |
                     ((imm << ( 2 - 0)) & 0b0000001111100))
        return 0x6001 | scrambled | (reg << 7)

    for i in range(100):
        reg = 2
        while reg == 2:
            reg = random.randint(1, 15)
        imm = random.randint(-0x20, 0x1F)
        dut.instr.value = encode_clui(reg, imm)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 1
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value == (imm << 12) & 0xffffffff
        
        assert dut.rd.value == reg

@cocotb.test()
async def test_branch(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    ops = [
        (InstructionBEQ, 0b0100, 0),
        (InstructionBNE, 0b0100, 1),
        (InstructionBLT, 0b0010, 0),
        (InstructionBLTU,  0b0011, 0),
        (InstructionBGE, 0b0010, 1),
        (InstructionBGEU, 0b0011, 1),
    ]

    for i in range(800):
        src_reg = random.randint(0, 15)
        src_reg2 = random.randint(0, 15)
        offset = random.randint(-2048, 2047) * 2
        op = random.choice(ops)

        dut.instr.value = op[0](src_reg, src_reg2, offset).encode()
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 1
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 4

        assert dut.alu_op.value == op[1]
        assert dut.mem_op.value & 1 == op[2]

        assert dut.rs1.value == src_reg
        assert dut.rs2.value == src_reg2
        assert dut.imm.value.signed_integer == offset

    def encode_cbeq(src_reg, offset, neq):
        scrambled = (((offset << (12 - 8)) & 0b1000000000000) |
                     ((offset << (10 - 3)) & 0b0110000000000) |
                     ((offset >> ( 6 - 5)) & 0b0000001100000) |
                     ((offset << ( 3 - 1)) & 0b0000000011000) |
                     ((offset >> ( 5 - 2)) & 0b0000000000100))
        if neq:
            return 0xE001 | scrambled | ((src_reg - 8) << 7)
        else:
            return 0xC001 | scrambled | ((src_reg - 8) << 7)

    for i in range(200):
        src_reg = random.randint(8, 15)
        offset = random.randint(-128, 127) * 2
        neq = random.choice((True, False))

        dut.instr.value = encode_cbeq(src_reg, offset, neq)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 1
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.alu_op.value == 0b0100
        assert dut.mem_op.value & 1 == (1 if neq else 0)

        assert dut.rs1.value == src_reg
        assert dut.rs2.value == 0
        assert dut.imm.value.signed_integer == offset

@cocotb.test()
async def test_jalr(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    for i in range(100):
        reg = random.randint(0, 15)
        dest_reg = random.randint(0, 15)
        offset = random.randint(-2048, 2047)
        dut.instr.value = InstructionJALR(dest_reg, reg, offset).encode()
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 1
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 4

        assert dut.imm.value.signed_integer == offset
        
        assert dut.rs1.value == reg
        assert dut.rd.value == dest_reg

    def encode_cjalr(dest_reg, reg):
        if dest_reg == 1:
            return 0x9002 | (reg << 7)
        else:
            return 0x8002 | (reg << 7)

    for i in range(200):
        reg = random.randint(1, 15)
        dest_reg = random.randint(0, 1)
        dut.instr.value = encode_cjalr(dest_reg, reg)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 1
        assert dut.is_ret.value == (1 if reg == 1 and dest_reg == 0 else 0)
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value.signed_integer == 0
        
        assert dut.rs1.value == reg
        assert dut.rd.value == dest_reg


@cocotb.test()
async def test_jal(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    for i in range(100):
        dest_reg = random.randint(0, 15)
        offset = random.randint(-0x80000, 0x7FFFF) * 2
        dut.instr.value = InstructionJAL(dest_reg, offset).encode()
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 1
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 4

        assert dut.imm.value.signed_integer == offset

        assert dut.rd.value == dest_reg

    # C.J / C.JAL encoder
    def encode_cjal(dest_reg, offset):
        scrambled = (((offset << (12 - 11)) & 0b1000000000000) |
                     ((offset << (11 -  4)) & 0b0100000000000) |
                     ((offset << ( 9 -  8)) & 0b0011000000000) |
                     ((offset >> (10 -  8)) & 0b0000100000000) |
                     ((offset << ( 7 -  6)) & 0b0000010000000) |
                     ((offset >> ( 7 -  6)) & 0b0000001000000) |
                     ((offset << ( 3 -  1)) & 0b0000000111000) |
                     ((offset >> ( 5 -  2)) & 0b0000000000100))
        if dest_reg == 1:
            return 0x2001 | scrambled
        else:
            return 0xA001 | scrambled

    for i in range(100):
        dest_reg = random.randint(0, 1)
        offset = random.randint(-0x400, 0x3FF) * 2
        dut.instr.value = encode_cjal(dest_reg, offset)
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 1
        assert dut.is_system.value == 0
        assert dut.instr_len.value == 2

        assert dut.imm.value.signed_integer == offset

        assert dut.rd.value == dest_reg        

@cocotb.test()
async def test_system(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    # Encoding for EBREAK is broken, so encode manually
    # ECALL, EBREAK, C.EBREAK
    encoded_instr = [0x73, 0x00100073, 0x9002]

    for instr in encoded_instr:
        dut.instr.value = instr
        await Timer(1, "ns")

        assert dut.is_load.value == 0
        assert dut.is_alu_imm.value == 0
        assert dut.is_auipc.value == 0
        assert dut.is_store.value == 0
        assert dut.is_alu_reg.value == 0
        assert dut.is_lui.value == 0
        assert dut.is_branch.value == 0
        assert dut.is_jalr.value == 0
        assert dut.is_jal.value == 0
        assert dut.is_system.value == 1
        assert dut.instr_len.value == (4 if (instr & 3) == 3 else 2)

        assert dut.imm.value == (0 if (instr == 0x73) else 1)