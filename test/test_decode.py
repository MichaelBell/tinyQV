import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

from riscvmodel.insn import *

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

        assert dut.imm.value.signed_integer == offset
        assert dut.alu_op.value == 0  # ADD
        assert dut.mem_op.value == op[1]
        
        assert dut.rs1.value == base_reg
        assert dut.rd.value == reg

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

        if op[2]: assert dut.imm.value.signed_integer == imm
        else: assert dut.imm.value & 0x1F == imm
        assert dut.alu_op.value == op[1]

        assert dut.rs1.value == src_reg
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

        assert dut.alu_op.value == op[1]

        assert dut.rs1.value == src_reg
        assert dut.rs2.value == src_reg2
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

        assert dut.imm.value == imm << 12
        
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

        assert dut.alu_op.value == op[1]
        assert dut.mem_op.value & 1 == op[2]

        assert dut.rs1.value == src_reg
        assert dut.rs2.value == src_reg2
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

        assert dut.imm.value.signed_integer == offset
        
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
        reg = random.randint(0, 15)
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

        assert dut.imm.value.signed_integer == offset
        
        assert dut.rd.value == dest_reg

@cocotb.test()
async def test_system(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    for i in range(100):
        dut.instr.value = InstructionECALL().encode()
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

