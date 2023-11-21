import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

from riscvmodel.insn import *
from riscvmodel.regnames import x0, x1, x2, x5

@cocotb.test()
async def test_load_store(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    dut.load_data_ready.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rstn.value = 1

    for i in range(400):
        reg = random.randint(5, 15)
        # base_reg = random.randint(0, 15)
        offset = random.randint(-2048, 2047)
        val = random.randint(0, 0xFFFFFFFF)
        dut.instr.value = InstructionLW(reg, 0, offset).encode()
        dut.data_in.value = val

        await ClockCycles(dut.clk, 1)
        if i != 0:
            assert dut.address_ready.value == 1
            assert dut.addr_out.value.signed_integer == last_offset
            assert dut.data_out.value == last_val
        await ClockCycles(dut.clk, 7)
        assert dut.instr_complete.value == 0
        dut.load_data_ready.value = 1 # This is probably impossible (address is not finished generating yet!), but should work
        await ClockCycles(dut.clk, 1)
        assert dut.address_ready.value == 1
        assert dut.addr_out.value.signed_integer == offset
        await ClockCycles(dut.clk, 7)
        assert dut.instr_complete.value == 1
        dut.load_data_ready.value = 0

        dut.instr.value = InstructionSW(0, reg, offset).encode()
        dut.data_in.value = 0

        await ClockCycles(dut.clk, 8)
        assert dut.instr_complete.value == 1
        last_val = val
        last_offset = offset

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

async def get_reg_value(dut, reg):
    dut.instr.value = InstructionSW(0, reg, 0).encode()
    dut.data_in.value = 0

    assert dut.address_ready.value == 0
    await ClockCycles(dut.clk, 8)
    assert dut.instr_complete.value == 1
    assert dut.address_ready.value == 0
    dut.instr.value = InstructionNOP().encode()
    await ClockCycles(dut.clk, 1)
    assert dut.address_ready.value == 1
    assert dut.addr_out.value.signed_integer == 0
    value = dut.data_out.value
    await ClockCycles(dut.clk, 7)
    assert dut.address_ready.value == 0
    assert dut.instr_complete.value == 1
    return value

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
async def test_random(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1

    seed = random.randint(0, 0xFFFFFFFF)
    #seed = 2843241462
    debug = False
    for test in range(100):
        random.seed(seed + test)
        dut._log.info("Running test with seed {}".format(seed + test))
        for i in range(1, 16):
            if i == 3: reg[i] = 0x1000
            elif i == 4: reg[i] = 0x10000000
            else:
                reg[i] = random.randint(-2048, 2047)
                if debug: print("Set reg {} to {}".format(i, reg[i]))
                await send_instr(dut, InstructionADDI(i, x0, reg[i]).encode())

        if True:
            for i in range(16):
                reg_value = (await get_reg_value(dut, i)).signed_integer
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
            await send_instr(dut, instr.encode(rd, rs1, arg2), instr.cycles)
            #if debug:
            #    assert await get_reg_value(dut, rd) == reg[rd] & 0xFFFFFFFF

        for i in range(16):
            reg_value = (await get_reg_value(dut, i)).signed_integer
            if debug: print("Reg x{} = {} should be {}".format(i, reg_value, reg[i]))
            assert reg_value & 0xFFFFFFFF == reg[i] & 0xFFFFFFFF
