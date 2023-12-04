import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

from riscvmodel.insn import *
from riscvmodel.regnames import x0, x1, x2, x3, x5

async def send_instr(dut, instr, fast=False):
    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    if not fast:
        await ClockCycles(dut.clk, 7)
    dut.instr_data_in.value = instr & 0xFFFF
    dut.instr_ready.value = 1
    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    if not fast:
        await ClockCycles(dut.clk, 7)
    dut.instr_data_in.value = (instr >> 16) & 0xFFFF
    dut.instr_ready.value = 1

async def read_reg(dut, reg):
    offset = random.randint(0, 0x7FF)
    instr = InstructionSW(x0, reg, offset).encode()
    await send_instr(dut, instr)

    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    assert dut.data_write_n.value == 0b11

    for i in range(24):
        await ClockCycles(dut.clk, 1)
        if dut.data_write_n.value != 0b11:
            assert dut.data_write_n.value == 0b10
            assert dut.data_addr.value == offset
            return dut.data_out.value

    assert False

async def expect_branch(dut, addr):
    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    assert dut.instr_fetch_restart.value == 0

    for i in range(24):
        await ClockCycles(dut.clk, 1)
        if dut.instr_fetch_restart.value == 1:
            assert dut.instr_addr.value == addr >> 1
            return

    assert False

async def load_reg(dut, reg, value):
    offset = random.randint(0, 0x7FF)
    instr = InstructionLW(reg, x0, offset).encode()
    await send_instr(dut, instr)

    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    assert dut.data_read_n.value == 0b11

    for i in range(24):
        await ClockCycles(dut.clk, 1)
        if dut.data_read_n.value != 0b11:
            assert dut.data_read_n.value == 0b10
            assert dut.data_addr.value == offset
            await ClockCycles(dut.clk, random.randint(1, 16))
            dut.data_in.value = value
            dut.data_ready.value = 1
            await ClockCycles(dut.clk, 1)
            dut.data_ready.value = 0
            assert dut.data_read_n.value == 0b11
            break
    else:
        assert False

async def start(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 1
    await ClockCycles(dut.clk, 1)
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.instr_fetch_started.value = 0
    dut.instr_fetch_stopped.value = 0
    dut.instr_data_in.value = 0
    dut.instr_ready.value = 0
    dut.data_ready.value = 0
    dut.data_in.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    await ClockCycles(dut.clk, 1)
    assert dut.instr_addr.value == 0
    assert dut.instr_fetch_restart.value == 1
    assert dut.instr_fetch_stall.value == 0
    assert dut.data_write_n.value == 0b11
    assert dut.data_read_n.value == 0b11

    dut.instr_fetch_started.value = 1

    return clock

@cocotb.test()
async def test_basic(dut):
    await start(dut)

    await send_instr(dut, InstructionADDI(x1, x0, 0x100).encode())
    await send_instr(dut, InstructionADDI(x2, x0, 0x111).encode())
    await send_instr(dut, InstructionADDI(x1, x2, 0x23).encode())

    assert await read_reg(dut, x1) == 0x134
    await load_reg(dut, x1, 0x47654321)

    await send_instr(dut, InstructionADDI(x2, x1, 0x23).encode())
    assert await read_reg(dut, x2) == 0x47654344


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
]

@cocotb.test()
async def test_random_alu(dut):
    await start(dut)

    seed = random.randint(0, 0xFFFFFFFF)
    #seed = 2843241462
    debug = False
    for test in range(100):
        random.seed(seed + test)
        dut._log.info("Running test with seed {}".format(seed + test))
        for i in range(1, 16):
            if i == 3: reg[i] = 0x1000
            elif i == 4: reg[i] = 0x8000000
            else:
                reg[i] = random.randint(-0x80000000, 0x7FFFFFFF)
                if debug: print("Set reg {} to {}".format(i, reg[i]))
                await load_reg(dut, i, reg[i])

        if False:
            for i in range(16):
                reg_value = (await read_reg(dut, i)).signed_integer
                if debug: print("Reg {} is {}".format(i, reg_value))
                assert reg_value == reg[i]

        last_instr = ops[0]
        for i in range(25):
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
            await send_instr(dut, instr.encode(rd, rs1, arg2))
            #if debug:
            #    assert await read_reg(dut, rd) == reg[rd] & 0xFFFFFFFF

        for i in range(16):
            reg_value = (await read_reg(dut, i)).signed_integer
            if debug: print("Reg x{} = {} should be {}".format(i, reg_value, reg[i]))
            assert reg_value & 0xFFFFFFFF == reg[i] & 0xFFFFFFFF

@cocotb.test()
async def test_jump(dut):
    await start(dut)

    await send_instr(dut, InstructionJAL(x1, 0x5678).encode())
    await expect_branch(dut, 0x5678)
    assert await read_reg(dut, x1) == 0x4

    await send_instr(dut, InstructionADDI(x1, x0, 0x40).encode())
    await send_instr(dut, InstructionADDI(x1, x0, 0x100).encode())
    await send_instr(dut, InstructionJAL(x2, -0x1000).encode())
    await send_instr(dut, InstructionADDI(x1, x0, 0x80).encode(), True)
    await expect_branch(dut, 0x4684)
    assert await read_reg(dut, x2) == 0x5688
    assert await read_reg(dut, x1) == 0x100

    await send_instr(dut, InstructionJALR(x2, x1, 0x20).encode())
    await expect_branch(dut, 0x120)
    assert await read_reg(dut, x2) == 0x4690

    await send_instr(dut, InstructionAUIPC(x1, 0x1).encode())
    await send_instr(dut, InstructionJALR(x2, x1, -0x20).encode())
    await expect_branch(dut, 0x1104)
    assert await read_reg(dut, x2) == 0x12C

@cocotb.test()
async def test_branch(dut):
    await start(dut)

    await send_instr(dut, InstructionADDI(x1, x0, 0x200).encode())
    await send_instr(dut, InstructionADDI(x2, x0, -0x200).encode())
    await send_instr(dut, InstructionBEQ(x0, x1, 0x20).encode())
    await send_instr(dut, InstructionBNE(x0, x1, 0x20).encode())
    await expect_branch(dut, 0x2C)
    await send_instr(dut, InstructionBLT(x2, x1, -0x1C).encode())
    await expect_branch(dut, 0x10)
    await send_instr(dut, InstructionBGE(x2, x1, 0x20).encode())
    await send_instr(dut, InstructionBLTU(x2, x1, -0x20).encode())
    await send_instr(dut, InstructionBGEU(x2, x1, 0x20).encode())
    await expect_branch(dut, 0x38)
