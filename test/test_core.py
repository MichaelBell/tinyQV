import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

from riscvmodel.insn import *
from riscvmodel.regnames import x0, x1, x2, x3, x5, x6
from riscvmodel import csrnames

from core_instr import *

@cocotb.test()
async def test_load_store(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    dut.load_data_ready.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rstn.value = 1

    ops = [
        (InstructionSW, 0xFFFFFFFF),
        (InstructionSH, 0xFFFF),
        (InstructionSB, 0xFF),
    ]

    for i in range(400):
        reg = random.randint(5, 15)
        offset = random.randint(-2048, 2047)
        val = random.randint(0, 0xFFFFFFFF)
        dut.instr.value = InstructionLW(reg, x3, offset).encode()
        dut.data_in.value.assign("X")

        await ClockCycles(dut.clk, 8)
        assert dut.instr_complete.value == 0
        assert dut.address_ready.value == 1
        assert dut.addr_out.value.signed_integer == offset + 0x1000400
        await ClockCycles(dut.clk, 8)
        dut.load_data_ready.value = 1
        dut.data_in.value = val
        await ClockCycles(dut.clk, 8)
        assert dut.instr_complete.value == 1
        dut.load_data_ready.value = 0
        dut.data_in.value.assign("X")

        op = random.choice(ops)
        dut.instr.value = op[0](x3, reg, offset).encode()

        await ClockCycles(dut.clk, 8)
        assert dut.instr_complete.value == 1
        assert dut.address_ready.value == 1
        assert dut.addr_out.value.signed_integer == offset + 0x1000400
        assert dut.data_out.value == val & op[1]

async def send_instr(dut, instr, cycles=0):
    dut.instr.value = instr
    if cycles == 0:
        while True:
            await ClockCycles(dut.clk, 8)
            if dut.instr_complete.value: return
    else:
        while cycles > 1:
            await ClockCycles(dut.clk, 8)
            assert dut.instr_complete.value == 0
            cycles -= 1
        await ClockCycles(dut.clk, 8)
        assert dut.instr_complete.value == 1

def fix_hardcoded_reg_value(reg, val):
    if reg == 0: return 0
    elif reg == 3: return 0x1000400
    elif reg == 4: return 0x8000000
    return val

async def get_reg_value(dut, reg):
    dut.instr.value = InstructionSW(0, reg, 0).encode()
    dut.data_in.value = 0

    await ClockCycles(dut.clk, 8)
    assert dut.instr_complete.value == 1
    assert dut.address_ready.value == 1
    assert dut.addr_out.value.signed_integer == 0
    return dut.data_out.value

async def set_reg_value(dut, reg, val):
    offset = random.randint(-2048, 2047)
    dut.instr.value = InstructionLW(reg, x3, offset).encode()
    dut.data_in.value.assign("X")

    await ClockCycles(dut.clk, 8)
    assert dut.instr_complete.value == 0
    assert dut.address_ready.value == 1
    assert dut.addr_out.value.signed_integer == offset + 0x1000400
    dut.load_data_ready.value = 1
    dut.data_in.value = val
    await ClockCycles(dut.clk, 8)
    assert dut.instr_complete.value == 1
    dut.load_data_ready.value = 0
    dut.data_in.value.assign("X")

@cocotb.test()
async def test_load(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    dut.load_data_ready.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rstn.value = 1

    ops = [
        (InstructionLW, 0b010, -0x80000000, 0x7FFFFFFF),
        (InstructionLH, 0b001, -32768, 32767),
        (InstructionLB, 0b000, -128, 127),
        (InstructionLBU, 0b100, 0, 255),
        (InstructionLHU, 0b101, 0, 65536),
    ]

    for i in range(400):
        reg = random.randint(0, 15)
        offset = random.randint(-2048, 2047)
        op = random.choice(ops)
        val = random.randint(-0x80000000, 0x7FFFFFFF)
        dut.instr.value = op[0](reg, x3, offset).encode()
        dut.data_in.value.assign("X")
        await ClockCycles(dut.clk, 8)
        assert dut.instr_complete.value == 0
        assert dut.address_ready.value == 1
        assert dut.addr_out.value.signed_integer == offset + 0x1000400
        for cycle in range(random.randint(1, 20)):
            await ClockCycles(dut.clk, 8)
            assert dut.instr_complete.value == 0
        dut.load_data_ready.value = 1
        dut.data_in.value = val
        await ClockCycles(dut.clk, 8)
        assert dut.instr_complete.value == 1
        dut.load_data_ready.value = 0

        if op[1] & 0b100:
            if op[1] & 1:
                val = (val & 0xFFFF)
            else:
                val = (val & 0xFF)
        else:
            if (op[1] & 0b11) == 0b01:
                val = (val % 65536)
                if val > 32767: val -= 65536
            elif (op[1] & 0b11) == 0b00:
                val = (val % 256)
                if val > 127: val -= 256

        val = fix_hardcoded_reg_value(reg, val)

        assert (await get_reg_value(dut, reg)).signed_integer == val


@cocotb.test()
async def test_add(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    await send_instr(dut, InstructionADDI(x1, x0, 279).encode())
    await send_instr(dut, InstructionADDI(x2, x1, 3).encode())
    assert await get_reg_value(dut, x1) == 279
    assert await get_reg_value(dut, x2) == 282
    await send_instr(dut, InstructionADDI(x1, x0, 2).encode())
    assert await get_reg_value(dut, x1) == 2

    await send_instr(dut, InstructionADD(x2, x1, x1).encode())
    assert await get_reg_value(dut, x2) == 4
    await send_instr(dut, InstructionADD(x2, x2, x1).encode())
    assert await get_reg_value(dut, x2) == 6
    await send_instr(dut, InstructionADDI(x1, x2, 1).encode())
    assert await get_reg_value(dut, x1) == 7

    await send_instr(dut, InstructionLUI(x1, 0xffffc).encode())
    await send_instr(dut, InstructionADDI(x1, x0, 204).encode())
    await send_instr(dut, InstructionLUI(x2, 4).encode())
    await send_instr(dut, InstructionADDI(x2, x0, -204).encode())
    await send_instr(dut, InstructionADD(x1, x1, x2).encode())
    assert await get_reg_value(dut, x1) == 0


@cocotb.test()
async def test_lui(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    await send_instr(dut, InstructionLUI(x1, 279).encode())
    await send_instr(dut, InstructionADDI(x2, x1, 3).encode())
    assert await get_reg_value(dut, x1) == 279 << 12
    assert await get_reg_value(dut, x2) == (279 << 12) + 3

@cocotb.test()
async def test_auipc(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1
    dut.pc.value = 0x1234

    await send_instr(dut, InstructionAUIPC(x1, 0x279).encode())
    await send_instr(dut, InstructionADDI(x2, x1, 3).encode())
    assert await get_reg_value(dut, x1) == 0x27A234
    assert await get_reg_value(dut, x2) == 0x27A237

@cocotb.test()
async def test_slt(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    await send_instr(dut, InstructionADDI(x1, x0, 1).encode())
    await send_instr(dut, InstructionSLTI(x2, x1, 0).encode())
    await send_instr(dut, InstructionSLTI(x5, x1, 2).encode())
    assert await get_reg_value(dut, x2) == 0
    assert await get_reg_value(dut, x5) == 1

@cocotb.test()
async def test_czero(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    await send_instr(dut, InstructionADDI(x1, x0, 1).encode())
    await send_instr(dut, InstructionADDI(x2, x1, -1).encode())
    await send_instr(dut, InstructionADDI(x5, x1, 4).encode())
    await send_instr(dut, InstructionCZERO_EQZ(x6, x5, x2).encode())
    await send_instr(dut, InstructionCZERO_NEZ(x5, x5, x2).encode())
    assert await get_reg_value(dut, x5) == 5
    assert await get_reg_value(dut, x6) == 0

@cocotb.test()
async def test_jal(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1
    dut.pc.value = 0x8

    await send_instr(dut, InstructionJAL(x0, 0x2000).encode())
    assert dut.branch.value == 1
    assert dut.addr_out.value == 0x2008
    dut.pc.value = 0x2008
    await send_instr(dut, InstructionJAL(x2, -0x1000).encode())
    assert dut.branch.value == 1
    assert dut.addr_out.value == 0x1008
    assert await get_reg_value(dut, x2) == 0x200C

@cocotb.test()
async def test_jalr(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1
    dut.pc.value = 0x8

    await send_instr(dut, InstructionADDI(x1, x0, 0x200).encode())
    await send_instr(dut, InstructionJALR(x0, x1, 0x20).encode())
    assert dut.branch.value == 1
    assert dut.addr_out.value == 0x220
    dut.pc.value = 0x220
    await send_instr(dut, InstructionAUIPC(x1, 0).encode())
    await send_instr(dut, InstructionJALR(x2, x1, -0x120).encode())
    assert dut.branch.value == 1
    assert dut.addr_out.value == 0x100
    assert await get_reg_value(dut, x2) == 0x224
    dut.pc.value = 0x224
    await send_instr(dut, InstructionADDI(x1, x0, 0x100).encode())
    await send_instr(dut, InstructionJALR(x2, x1, 0x20).encode())
    assert dut.branch.value == 1
    assert dut.addr_out.value == 0x120
    assert await get_reg_value(dut, x2) == 0x228

@cocotb.test()
async def test_branch(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1
    dut.pc.value = 0x8

    await send_instr(dut, InstructionADDI(x1, x0, 0x200).encode())
    await send_instr(dut, InstructionADDI(x2, x0, -0x200).encode())
    await send_instr(dut, InstructionBEQ(x0, x1, 0x20).encode(), 1)
    assert dut.branch.value == 0
    await send_instr(dut, InstructionBNE(x0, x1, 0x20).encode(), 1)
    assert dut.branch.value == 1
    dut.pc.value = 0x28
    await send_instr(dut, InstructionBLT(x2, x1, -0x20).encode(), 1)
    assert dut.branch.value == 1
    dut.pc.value = 0x8
    await send_instr(dut, InstructionBGE(x2, x1, 0x20).encode(), 1)
    assert dut.branch.value == 0
    await send_instr(dut, InstructionBLTU(x2, x1, -0x20).encode(), 1)
    assert dut.branch.value == 0
    await send_instr(dut, InstructionBGEU(x2, x1, 0x20).encode(), 1)
    assert dut.branch.value == 1
    dut.pc.value = 0x28
    await send_instr(dut, InstructionADDI(x1, x0, 0x31).encode())
    await send_instr(dut, InstructionBLTU(x0, x1, -0x20).encode(), 1)
    assert dut.branch.value == 1

    ops = [
        (InstructionBEQ, lambda a, b: a == b),
        (InstructionBNE, lambda a, b: a != b),
        (InstructionBLT, lambda a, b: a < b),
        (InstructionBGE, lambda a, b: a >= b),
        (InstructionBLTU, lambda a, b: (a & 0xFFFFFFFF) < (b & 0xFFFFFFFF)),
        (InstructionBGEU, lambda a, b: (a & 0xFFFFFFFF) >= (b & 0xFFFFFFFF)),
    ]

    seed = random.randint(0, 0xFFFFFFFF)
    dut._log.info("Using seed {}".format(seed))
    random.seed(seed)

    for i in range(400):
        r1 = random.randint(0, 15) 
        r2 = random.randint(0, 15) 
        a = random.randint(-15, 15)
        b = random.randint(-15, 15)
        offset = random.randint(-2048, 2047) * 2
        dut.pc.value = random.randint(1024, 0x3FF000) * 4
        await set_reg_value(dut, r1, a)
        await set_reg_value(dut, r2, b)
        a = fix_hardcoded_reg_value(r1, a)
        b = fix_hardcoded_reg_value(r2, b)
        if r1 == r2: a = b
        #assert (await get_reg_value(dut, r1)).signed_integer == a
        #assert (await get_reg_value(dut, r2)).signed_integer == b
        op = random.choice(ops)
        #print(a, b, op)
        await send_instr(dut, op[0](r1, r2, offset).encode())
        assert dut.branch.value == op[1](a, b)

    for i in range(400):
        r1 = random.randint(0, 15) 
        r2 = random.randint(0, 15) 
        a = random.randint(-0x80000000, 0x7FFFFFFF)
        b = random.randint(-0x80000000, 0x7FFFFFFF)
        offset = random.randint(-2048, 2047) * 2
        dut.pc.value = random.randint(1024, 0x3FF000) * 4
        await set_reg_value(dut, r1, a)
        await set_reg_value(dut, r2, b)
        a = fix_hardcoded_reg_value(r1, a)
        b = fix_hardcoded_reg_value(r2, b)
        if r1 == r2: a = b
        op = random.choice(ops)
        await send_instr(dut, op[0](r1, r2, offset).encode())
        assert dut.branch.value == op[1](a, b)

@cocotb.test()
async def test_trap(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1
    dut.pc.value = 0x8

    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.mstatus).encode())
    assert await get_reg_value(dut, x1) == 0xC
    await send_instr(dut, InstructionECALL().encode())
    assert dut.branch.value == 1
    assert dut.addr_out.value == 0x4
    dut.pc.value = 0x4
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.mcause).encode())
    assert await get_reg_value(dut, x1) == 11
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.mepc).encode())
    assert await get_reg_value(dut, x1) == 0x8
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.mstatus).encode())
    assert await get_reg_value(dut, x1) == 0x80
    await send_instr(dut, InstructionMRET().encode())
    assert dut.branch.value == 1
    assert dut.addr_out.value == 0x8
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.mstatus).encode())
    assert await get_reg_value(dut, x1) == 0x8C

    dut.pc.value = 0x723456
    await send_instr(dut, 0x00100073)   # InstructionEBREAK().encode()
    assert dut.branch.value == 1
    assert dut.addr_out.value == 0x4
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mcause).encode())
    assert await get_reg_value(dut, x2) == 3
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.mstatus).encode())
    assert await get_reg_value(dut, x1) == 0x80
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.mepc).encode())
    assert await get_reg_value(dut, x1) == 0x723456
    await send_instr(dut, InstructionADDI(x1, x1, 0x114).encode())
    await send_instr(dut, InstructionCSRRW(x0, x1, csrnames.mepc).encode())
    await send_instr(dut, InstructionMRET().encode())
    assert dut.branch.value == 1
    assert dut.addr_out.value == 0x723456 + 0x114
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.mstatus).encode())
    assert await get_reg_value(dut, x1) == 0x8C

@cocotb.test()
async def test_shift(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    await send_instr(dut, InstructionADDI(x1, x0, 1).encode())
    await send_instr(dut, InstructionSLLI(x2, x1, 4).encode())
    assert await get_reg_value(dut, x2) == 16
    await send_instr(dut, InstructionSLLI(x5, x1, 2).encode())
    assert await get_reg_value(dut, x5) == 4
    await send_instr(dut, InstructionSLLI(x5, x1, 0).encode())
    assert await get_reg_value(dut, x5) == 1
    await send_instr(dut, InstructionSLLI(x5, x1, 31).encode())
    assert await get_reg_value(dut, x5) == 0x80000000

    await send_instr(dut, InstructionADDI(x5, x0, 1).encode())
    await send_instr(dut, InstructionSLL(x2, x1, x5).encode())
    assert await get_reg_value(dut, x2) == 2
    await send_instr(dut, InstructionADDI(x5, x5, 15).encode())
    await send_instr(dut, InstructionSLL(x5, x1, x5).encode())
    assert await get_reg_value(dut, x5) == 0x10000

    await send_instr(dut, InstructionSRLI(x2, x5, 1).encode())
    assert await get_reg_value(dut, x2) == 0x8000
    await send_instr(dut, InstructionSRLI(x2, x5, 4).encode())
    assert await get_reg_value(dut, x2) == 0x1000

    await send_instr(dut, InstructionSRL(x2, x5, x1).encode())
    assert await get_reg_value(dut, x2) == 0x8000
    await send_instr(dut, InstructionADDI(x1, x0, 15).encode())
    await send_instr(dut, InstructionSRL(x2, x5, x1).encode())
    assert await get_reg_value(dut, x2) == 2
    await send_instr(dut, InstructionADDI(x1, x0, 17).encode())
    await send_instr(dut, InstructionSRL(x2, x5, x1).encode())
    assert await get_reg_value(dut, x2) == 0

    await send_instr(dut, InstructionSRAI(x2, x5, 15).encode())
    assert await get_reg_value(dut, x2) == 2

    await send_instr(dut, InstructionSLLI(x5, x5, 15).encode())

    await send_instr(dut, InstructionSRAI(x2, x5, 1).encode())
    assert await get_reg_value(dut, x2) == 0xC0000000
    await send_instr(dut, InstructionADDI(x1, x0, 15).encode())
    await send_instr(dut, InstructionSRA(x2, x5, x1).encode())
    assert await get_reg_value(dut, x2) == 0xFFFF0000
    await send_instr(dut, InstructionADDI(x1, x0, 17).encode())
    await send_instr(dut, InstructionSRA(x2, x5, x1).encode())
    assert await get_reg_value(dut, x2) == 0xFFFFC000


@cocotb.test()
async def test_multiply(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    await send_instr(dut, InstructionADDI(x1, x0, 2).encode())
    await send_instr(dut, InstructionADDI(x2, x0, 3).encode())
    await send_instr(dut, InstructionMUL16(x5, x1, x2).encode())
    assert await get_reg_value(dut, x5) == 6
    await send_instr(dut, InstructionMUL16(x2, x5, x1).encode())
    assert await get_reg_value(dut, x2) == 12
    await send_instr(dut, InstructionMUL16(x2, x5, x2).encode())
    assert await get_reg_value(dut, x2) == 12*6

reg = [0] * 16

# Each Op does reg[d] = fn(a, b)
# fn will access reg global array
class Op:
    def __init__(self, rvm_insn, fn, cycles, name):
        self.rvm_insn = rvm_insn
        self.fn = fn
        self.name = name
        self.cycles = cycles
    
    def execute_fn(self, rd, rs1, arg2):
        if rd != 0 and rd != 3 and rd != 4:
            reg[rd] = self.fn(rs1, arg2)
            while reg[rd] < -0x80000000: reg[rd] += 0x100000000
            while reg[rd] > 0x7FFFFFFF:  reg[rd] -= 0x100000000

    def encode(self, rd, rs1, arg2):
        return self.rvm_insn(rd, rs1, arg2).encode()

ops = [
    Op(InstructionADDI, lambda rs1, imm: reg[rs1] + imm, 1, "+i"),
    Op(InstructionADD, lambda rs1, rs2: reg[rs1] + reg[rs2], 1, "+"),
    Op(InstructionSUB, lambda rs1, rs2: reg[rs1] - reg[rs2], 1, "-"),
    Op(InstructionANDI, lambda rs1, imm: reg[rs1] & imm, 1, "&i"),
    Op(InstructionAND, lambda rs1, rs2: reg[rs1] & reg[rs2], 1, "&"),
    Op(InstructionORI, lambda rs1, imm: reg[rs1] | imm, 1, "|i"),
    Op(InstructionOR, lambda rs1, rs2: reg[rs1] | reg[rs2], 1, "|"),
    Op(InstructionXORI, lambda rs1, imm: reg[rs1] ^ imm, 1, "^i"),
    Op(InstructionXOR, lambda rs1, rs2: reg[rs1] ^ reg[rs2], 1, "^"),
    Op(InstructionSLTI, lambda rs1, imm: 1 if reg[rs1] < imm else 0, 2, "<i"),
    Op(InstructionSLT, lambda rs1, rs2: 1 if reg[rs1] < reg[rs2] else 0, 2, "<"),
    Op(InstructionSLTIU, lambda rs1, imm: 1 if (reg[rs1] & 0xFFFFFFFF) < (imm & 0xFFFFFFFF) else 0, 2, "<iu"),
    Op(InstructionSLTU, lambda rs1, rs2: 1 if (reg[rs1] & 0xFFFFFFFF) < (reg[rs2] & 0xFFFFFFFF) else 0, 2, "<u"),
    Op(InstructionSLLI, lambda rs1, imm: reg[rs1] << imm, 2, "<<i"),
    Op(InstructionSLL, lambda rs1, rs2: reg[rs1] << (reg[rs2] & 0x1F), 2, "<<"),
    Op(InstructionSRLI, lambda rs1, imm: (reg[rs1] & 0xFFFFFFFF) >> imm, 2, ">>li"),
    Op(InstructionSRL, lambda rs1, rs2: (reg[rs1] & 0xFFFFFFFF) >> (reg[rs2] & 0x1F), 2, ">>l"),
    Op(InstructionSRAI, lambda rs1, imm: reg[rs1] >> imm, 2, ">>i"),
    Op(InstructionSRA, lambda rs1, rs2: reg[rs1] >> (reg[rs2] & 0x1F), 2, ">>"),
    Op(InstructionMUL16, lambda rs1, rs2: reg[rs1] * (reg[rs2] & 0xFFFF), 2, "*"),
    Op(InstructionCZERO_EQZ, lambda rs1, rs2: 0 if reg[rs2] == 0 else reg[rs1], 0, "?0"),
    Op(InstructionCZERO_NEZ, lambda rs1, rs2: 0 if reg[rs2] != 0 else reg[rs1], 0, "?!0"),
]

@cocotb.test()
async def test_random(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    seed = random.randint(0, 0xFFFFFFFF)
    #seed = 1146792006
    debug = False
    for test in range(100):
        random.seed(seed + test)
        dut._log.info("Running test with seed {}".format(seed + test))
        for i in range(1, 16):
            if i == 3: reg[i] = 0x1000400
            elif i == 4: reg[i] = 0x8000000
            else:
                reg[i] = random.randint(-0x80000000, 0x7FFFFFFF)
                if debug: print("Set reg {} to {}".format(i, reg[i]))
                await set_reg_value(dut, i, reg[i])

        if False:
            for i in range(16):
                reg_value = (await get_reg_value(dut, i)).signed_integer
                if debug: print("Reg {} is {}".format(i, reg_value))
                assert reg_value == reg[i]

        last_instr = ops[0]
        for i in range(30):
            while True:
                try:
                    instr = random.choice(ops)
                    rd = random.randint(0, 15)
                    rs1 = random.randint(0, 15)
                    arg2 = random.randint(0, 15)  # TODO

                    instr.execute_fn(rd, rs1, arg2)
                    break
                except ValueError:
                    pass

            if debug: print("x{} = x{} {} {}, now {} {:08x}".format(rd, rs1, arg2, instr.name, reg[rd], instr.encode(rd, rs1, arg2)))
            await send_instr(dut, instr.encode(rd, rs1, arg2), instr.cycles)
            #if debug:
            #    assert await get_reg_value(dut, rd) == reg[rd] & 0xFFFFFFFF

        for i in range(16):
            reg_value = (await get_reg_value(dut, i)).signed_integer
            if debug: print("Reg x{} = {} should be {}".format(i, reg_value, reg[i]))
            assert reg_value & 0xFFFFFFFF == reg[i] & 0xFFFFFFFF
