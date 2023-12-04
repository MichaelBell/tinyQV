import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

@cocotb.test()
async def test_mcycle(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rstn.value = 1
    dut.add.value = 1
    await ClockCycles(dut.clk, 1)

    for i in range(20):
        await ClockCycles(dut.clk, 8)
        assert dut.val.value == i


@cocotb.test()
async def test_minstret(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rstn.value = 1
    dut.add.value = 0
    await ClockCycles(dut.clk, 9)
    
    retired = 0
    last_retired = 0
    last_retired2 = 0
    for i in range(100):
        assert dut.val.value == last_retired2
        last_retired2 = last_retired
        await ClockCycles(dut.clk, 7)
        last_retired = retired
        x = random.randint(0, 1)
        retired += x
        dut.add.value = x
        await ClockCycles(dut.clk, 1)
