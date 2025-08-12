import random

import cocotb
import cocotb.utils
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

from riscvmodel.insn import *
from riscvmodel.regnames import x0, x1, x2, x3, x5
from riscvmodel import csrnames

from core_instr import *

async def send_instr(dut, instr, fast=False, len=4):
    await ClockCycles(dut.clk, 1)
    dut.instr_fetch_started.value = 0
    dut.instr_ready.value = 0
    dut.time_pulse.value = 0
    if not fast:
        await ClockCycles(dut.clk, 7)
    dut.instr_data_in.value = instr & 0xFFFF
    dut.instr_ready.value = 1
    if len == 4:
        await ClockCycles(dut.clk, 1)
        dut.instr_ready.value = 0
        if not fast:
            await ClockCycles(dut.clk, 7)
        dut.instr_data_in.value = (instr >> 16) & 0xFFFF
        dut.instr_ready.value = 1

async def expect_store(dut, addr, random_delay=True):
    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    assert dut.data_write_n.value == 0b11

    for i in range(24):
        await ClockCycles(dut.clk, 1)
        if dut.data_write_n.value != 0b11:
            assert dut.data_write_n.value == 0b10
            assert dut.data_addr.value == addr
            val = dut.data_out.value
            if random_delay:
                await ClockCycles(dut.clk, random.randint(1, 16))
            else:
                await ClockCycles(dut.clk, 1)
            dut.data_ready.value = 1
            assert dut.data_out.value == val
            await ClockCycles(dut.clk, 1)
            dut.data_ready.value = 0
            await Timer(1, "ns")
            assert dut.data_write_n.value == 0b11
            return val

    assert False

async def read_reg(dut, reg, random_delay=True):
    offset = random.randint(0, 0x7FF)
    instr = InstructionSW(x0, reg, offset).encode()
    await send_instr(dut, instr)

    return await expect_store(dut, offset, random_delay)

async def expect_branch(dut, addr, early=False):
    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    if not early:
        assert dut.instr_fetch_restart.value == 0

    for i in range(24):
        await ClockCycles(dut.clk, 1)
        if dut.instr_fetch_restart.value == 1:
            assert dut.instr_addr.value == addr >> 1
            dut.instr_fetch_started.value = 1
            return

    assert False

async def expect_load(dut, addr, val):
    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    assert dut.data_read_n.value == 0b11

    for i in range(24):
        await ClockCycles(dut.clk, 1)
        if dut.data_read_n.value != 0b11:
            assert dut.data_read_n.value == 0b10
            assert dut.data_addr.value == addr
            await ClockCycles(dut.clk, random.randint(1, 16))
            dut.data_in.value = val
            dut.data_ready.value = 1
            await ClockCycles(dut.clk, 1)
            dut.data_ready.value = 0
            await Timer(1, "ns")
            assert dut.data_read_n.value == 0b11
            break
    else:
        assert False

async def load_reg(dut, reg, value):
    offset = random.randint(0, 0x7FF)
    instr = InstructionLW(reg, x0, offset).encode()
    await send_instr(dut, instr)

    await expect_load(dut, offset, value)

async def start(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 1
    await ClockCycles(dut.clk, 1)
    dut.rstn.value = 0
    dut.interrupt_req.value = 0
    dut.time_pulse.value = 0
    await ClockCycles(dut.clk, 2)
    dut.instr_fetch_started.value = 0
    dut.instr_fetch_stopped.value = 0
    dut.instr_data_in.value = 0
    dut.instr_ready.value = 0
    dut.data_ready.value = 0
    dut.data_in.value = 0
    await ClockCycles(dut.clk, 10)
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
    Op(InstructionMUL16, lambda rs1, rs2: reg[rs1] * (reg[rs2] & 0xFFFF), 2, "*"),
    Op(InstructionCZERO_EQZ, lambda rs1, rs2: 0 if reg[rs2] == 0 else reg[rs1], 0, "?0"),
    Op(InstructionCZERO_NEZ, lambda rs1, rs2: 0 if reg[rs2] != 0 else reg[rs1], 0, "?!0"),
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
            if i == 3: reg[i] = 0x1000400
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
    await expect_branch(dut, 0x4684, True)
    assert await read_reg(dut, x2) == 0x5688
    assert await read_reg(dut, x1) == 0x100

    await send_instr(dut, InstructionJALR(x2, x1, 0x20).encode())
    await expect_branch(dut, 0x120)
    assert await read_reg(dut, x2) == 0x4690

    await send_instr(dut, InstructionAUIPC(x1, 0x1).encode())
    await send_instr(dut, InstructionJALR(x2, x1, -0x20).encode())
    await expect_branch(dut, 0x1104)
    assert await read_reg(dut, x2) == 0x12C

    def encode_cjalr(dest_reg, reg):
        if dest_reg == 1:
            return 0x9002 | (reg << 7)
        else:
            return 0x8002 | (reg << 7)

    await send_instr(dut, InstructionADDI(x1, x1, 0x40).encode())
    await send_instr(dut, encode_cjalr(x0, x1))
    await expect_branch(dut, 0x1164, True)

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

@cocotb.test()
async def test_csr(dut):
    await start(dut)
    start_sim_time = cocotb.utils.get_sim_time("ns")

    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.cycle - 0x1000).encode())
    assert await read_reg(dut, x1, False) == 3
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.cycle - 0x1000).encode())
    assert await read_reg(dut, x2, False) == 9
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.instret - 0x1000).encode())
    assert await read_reg(dut, x1, False) == 4
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.instret - 0x1000).encode())
    assert await read_reg(dut, x1, False) == 6
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.cycle - 0x1000).encode())
    assert await read_reg(dut, x2, False) == 27
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.misa).encode())
    assert await read_reg(dut, x1, False) == 0x40000014
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.time - 0x1000).encode())
    assert await read_reg(dut, x1, False) == 39 // 8

    # Test time wrap
    nop = send_instr(dut, InstructionNOP().encode())
    count = ((cocotb.utils.get_sim_time("ns") - start_sim_time) // 4) % 8
    while count != 7:
        await ClockCycles(dut.clk, 1)
        count = (count + 1) % 8

    dut.cpu.i_core.i_cycles.register.value = 0xFFFFFEFF

    await nop
    await send_instr(dut, InstructionNOP().encode())
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.time - 0x1000).encode())
    assert await read_reg(dut, x1, False) == 0x1FFFFFFE
    for i in range(5):
        await send_instr(dut, InstructionNOP().encode())
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.time - 0x1000).encode())
    assert await read_reg(dut, x1, False) == 0x20000000

    nop = send_instr(dut, InstructionNOP().encode())
    count = ((cocotb.utils.get_sim_time("ns") - start_sim_time) // 4) % 8
    while count != 7:
        await ClockCycles(dut.clk, 1)
        count = (count + 1) % 8

    dut.cpu.i_core.i_cycles.register.value = 0xFFFFFEFF

    await nop
    await send_instr(dut, InstructionNOP().encode())
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.time - 0x1000).encode())
    assert await read_reg(dut, x1, False) == 0x3FFFFFFE
    for i in range(5):
        await send_instr(dut, InstructionNOP().encode())
    await send_instr(dut, InstructionCSRRS(x1, x0, csrnames.time - 0x1000).encode())
    assert await read_reg(dut, x1, False) == 0x40000000


@cocotb.test()
async def test_interrupt(dut):
    await start(dut)

    # Set mtimecmp to 1 which will clear the timer interrupt
    await send_instr(dut, InstructionADDI(x1, x0, 1).encode())
    await send_instr(dut, InstructionSW(x0, x1, -0xfc).encode())

    # Jump to a different address
    await send_instr(dut, InstructionJAL(x0, 0xf8).encode())
    await expect_branch(dut, 0x100)

    # Assert interrupt, this should latch but no interrupt yet
    dut.interrupt_req.value = 1
    await send_instr(dut, InstructionNOP().encode())
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mip).encode())
    dut.interrupt_req.value = 0
    assert await read_reg(dut, x2, False) == 0x10000
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mip).encode())
    assert await read_reg(dut, x2, False) == 0x10000
    await send_instr(dut, InstructionLUI(x1, 0x10).encode())

    # Enable the interrupt, it immediately fires
    await send_instr(dut, InstructionCSRRW(x0, x1, csrnames.mie).encode())
    await expect_branch(dut, 0x8)

    # Interrupts now disabled
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mstatus).encode())
    assert await read_reg(dut, x2, False) == 0x80
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mepc).encode())
    assert await read_reg(dut, x2, False) == 0x11C
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mcause).encode())
    assert await read_reg(dut, x2, False) == 0x80000010

    # Ack the interrupt
    await send_instr(dut, InstructionCSRRC(x0, x1, csrnames.mip).encode())
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mip).encode())
    assert await read_reg(dut, x2, False) == 0
    await send_instr(dut, InstructionMRET().encode())
    await expect_branch(dut, 0x11C)
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mstatus).encode())
    assert await read_reg(dut, x2, False) == 0x8C

    # Raise a persistent interrupt
    dut.interrupt_req.value = 4
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mip).encode())
    assert await read_reg(dut, x2, False) == 0x40000
    dut.interrupt_req.value = 0
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mip).encode())
    assert await read_reg(dut, x2, False) == 0

    dut.interrupt_req.value = 4
    await send_instr(dut, InstructionLUI(x1, 0x40).encode())
    await send_instr(dut, InstructionCSRRW(x0, x1, csrnames.mie).encode())
    await expect_branch(dut, 0x8)

    # Interrupts now disabled
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mstatus).encode())
    assert await read_reg(dut, x2, False) == 0x80
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mcause).encode())
    assert await read_reg(dut, x2, False) == 0x80000012

    # Clear the interrupt
    dut.interrupt_req.value = 0
    await send_instr(dut, InstructionMRET().encode())
    await expect_branch(dut, 0x13C)
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mstatus).encode())
    assert await read_reg(dut, x2, False) == 0x8C

    # Enable and assert interrupt
    await send_instr(dut, InstructionLUI(x1, 0x20).encode())
    await send_instr(dut, InstructionCSRRW(x0, x1, csrnames.mie).encode())
    dut.interrupt_req.value = 2
    await expect_branch(dut, 0x8)
    dut.interrupt_req.value = 2

    # Interrupts now disabled
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mstatus).encode())
    assert await read_reg(dut, x2, False) == 0x80
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mcause).encode())
    assert await read_reg(dut, x2, False) == 0x80000011

    # Trap, this is a double fault so causes reset
    await send_instr(dut, 0x00100073) # EBREAK
    await expect_branch(dut, 0)
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mcause).encode())
    assert await read_reg(dut, x2, False) == 0x3
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mip).encode())
    assert await read_reg(dut, x2, False) == 0
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mie).encode())
    assert await read_reg(dut, x2, False) == 0

    # Disable interrupts and then break, this is OK
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mstatus).encode())
    assert await read_reg(dut, x2, False) == 0xC
    await send_instr(dut, InstructionADDI(x1, x0, 0x8).encode())
    await send_instr(dut, InstructionCSRRC(x0, x1, csrnames.mstatus).encode())
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mstatus).encode())
    assert await read_reg(dut, x2, False) == 0x4
    await send_instr(dut, 0x00100073) # EBREAK
    await expect_branch(dut, 4)
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mcause).encode())
    assert await read_reg(dut, x2, False) == 0x3
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mstatus).encode())
    assert await read_reg(dut, x2, False) == 0x0

    # A second break is a double fault
    await send_instr(dut, 0x00100073) # EBREAK
    await expect_branch(dut, 0)

    # Jump to a different address
    await send_instr(dut, InstructionJAL(x0, 0x80).encode())
    await expect_branch(dut, 0x80)

    # Assert timer interrupt, but no interrupt yet as not enabled
    dut.time_pulse.value = 1
    await send_instr(dut, InstructionNOP().encode())
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mip).encode())
    assert await read_reg(dut, x2, False) == 0x80
    await send_instr(dut, InstructionADDI(x1, x0, 0x80).encode())

    # Enable the timer interrupt, it immediately fires
    await send_instr(dut, InstructionCSRRW(x0, x1, csrnames.mie).encode())
    await expect_branch(dut, 0x8)
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mcause).encode())
    assert await read_reg(dut, x2, False) == 0x80000007

    # Set mtime back to 0 which will clear the timer interrupt
    await send_instr(dut, InstructionSW(x0, x0, -0x100).encode())
    await send_instr(dut, InstructionNOP().encode())
    await send_instr(dut, InstructionCSRRS(x2, x0, csrnames.mip).encode())
    assert await read_reg(dut, x2, False) == 0


@cocotb.test()
async def test_context(dut):
    await start(dut)


    def encode_clcxt(imm, reg_seg, num_regs):
        scrambled = (((imm << (12 - 9)) & 0b1000000000000) |
                     ((imm << ( 6 - 4)) & 0b0000001000000) |
                     ((imm >> ( 6 - 5)) & 0b0000000100000) |
                     ((imm >> ( 7 - 3)) & 0b0000000011000) |
                     ((imm >> ( 5 - 2)) & 0b0000000000100))
        return 0x2002 | scrambled | (reg_seg << 10) | ((num_regs - 1) << 7)
    
    def encode_cscxt(imm, reg_seg, num_regs):
        scrambled = (((imm << (12 - 9)) & 0b1000000000000) |
                     ((imm << (11 - 4)) & 0b0100000000000) |
                     ((imm << (10 - 5)) & 0b0010000000000) |
                     ((imm << ( 7 - 6)) & 0b0001110000000))
        return 0xE000 | scrambled | (reg_seg << 5) | ((num_regs - 1) << 2)
    
    data = []
    for i in range(10):
        data.append(random.randint(0, (1 << 32) - 1))
    await load_reg(dut, x1, data[0])
    await load_reg(dut, x2, data[1])

    await send_instr(dut, encode_cscxt(0, 0, 2), False, 2)
    await expect_store(dut, 0x1000400) == data[0]
    await expect_store(dut, 0x1000404) == data[1]

    for i in range(8):
        await load_reg(dut, 8+i, data[2+i])

    await send_instr(dut, encode_cscxt(16, 1, 7), False, 2)
    for i in range(7):
        await expect_store(dut, 0x1000410 + ((i*4) & 0xF)) == data[i+3]

    for i in range(10):
        data[i] = random.randint(0, (1 << 32) - 1)

    await send_instr(dut, encode_clcxt(0, 0, 2), False, 2)
    await expect_load(dut, 0x1000400, data[0])
    await expect_load(dut, 0x1000404, data[1])

    assert await read_reg(dut, x1) == data[0]
    assert await read_reg(dut, x2) == data[1]

    await send_instr(dut, encode_clcxt(-0x200 & 0x3F0, 1, 7), False, 2)
    for i in range(7):
        await expect_load(dut, 0x1000200 + ((i*4) & 0xF), data[i+3])

    for i in range(7):
        assert await read_reg(dut, i+9) == data[i+3]
