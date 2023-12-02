import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

from riscvmodel.insn import *
from riscvmodel.regnames import x0, x1, x2, x3, x5

@cocotb.test()
async def test_reset(dut):
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

    instr = InstructionADDI(x1, x0, 0x100).encode()

    dut.instr_fetch_started.value = 1
    await ClockCycles(dut.clk, 8)
    dut.instr_data_in.value = instr & 0xFFFF
    dut.instr_ready.value = 1
    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    await ClockCycles(dut.clk, 7)
    dut.instr_data_in.value = (instr >> 16) & 0xFFFF
    dut.instr_ready.value = 1

    instr = InstructionADDI(x2, x0, 0x111).encode()
    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    await ClockCycles(dut.clk, 7)
    dut.instr_data_in.value = instr & 0xFFFF
    dut.instr_ready.value = 1
    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    await ClockCycles(dut.clk, 7)
    dut.instr_data_in.value = (instr >> 16) & 0xFFFF
    dut.instr_ready.value = 1

    instr = InstructionADDI(x1, x2, 0x23).encode()
    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    await ClockCycles(dut.clk, 7)
    dut.instr_data_in.value = instr & 0xFFFF
    dut.instr_ready.value = 1
    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0
    await ClockCycles(dut.clk, 7)
    dut.instr_data_in.value = (instr >> 16) & 0xFFFF
    dut.instr_ready.value = 1

    await ClockCycles(dut.clk, 1)
    dut.instr_ready.value = 0

    await ClockCycles(dut.clk, 31)

