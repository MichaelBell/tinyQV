import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

from riscvmodel.insn import *

@cocotb.test()
async def test_fake_load_store(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rstn.value = 1

    for i in range(400):
        reg = random.randint(5, 15)
        base_reg = random.randint(0, 15)
        offset = random.randint(-2048, 2047)
        val = random.randint(0, 0xFFFFFFFF)
        dut.instr.value = InstructionLW(reg, base_reg, offset).encode()
        dut.data_in.value = val

        await ClockCycles(dut.clk, 1)
        if i != 0:
            assert dut.data_out.value == last_val
        await ClockCycles(dut.clk, 7)

        dut.instr.value = InstructionSW(base_reg, reg, offset).encode()
        dut.data_in.value = 0

        await ClockCycles(dut.clk, 8)
        last_val = val