import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

@cocotb.test()
async def test_registers(reg):
    clock = Clock(reg.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    reg.rstn.value = 0
    await ClockCycles(reg.clk, 2)
    reg.rstn.value = 1
    reg.wr_en.value = 0

    reg.rs1.value = 1
    reg.rs2.value = 5
    reg.rd.value = 1
    reg.rd_in.value = 0x12345679
    await ClockCycles(reg.clk, 1)

    reg.wr_en.value = 1
    await ClockCycles(reg.clk, 1)
    assert reg.rs1_out.value == 0x12345679

    reg.wr_en.value = 0
    await ClockCycles(reg.clk, 1)
    assert reg.rs1_out.value == 0x12345679

    reg.wr_en.value = 1
    reg.rd_in.value = 0xA5948372
    await ClockCycles(reg.clk, 1)
    assert reg.rs1_out.value == 0xA5948372

    reg.wr_en.value = 0
    reg.rd.value = 5
    reg.rd_in.value = 0
    await ClockCycles(reg.clk, 1)
    assert reg.rs1_out.value == 0xA5948372

    reg.wr_en.value = 1
    await ClockCycles(reg.clk, 1)
    assert reg.rs2_out.value == 0
    reg.rd.value = 2
    reg.rs1.value = 5
    reg.rs2.value = 1
    reg.wr_en.value = 0
    await ClockCycles(reg.clk, 1)
    assert reg.rs1_out.value == 0
    assert reg.rs2_out.value == 0xA5948372

    reg.rd_in.value = 0x1111
    reg.wr_en.value = 1
    await ClockCycles(reg.clk, 1)
    reg.rd.value = 0
    reg.rs1.value = 1
    reg.rs2.value = 2
    reg.wr_en.value = 0
    await ClockCycles(reg.clk, 1)
    assert reg.rs1_out.value == 0xA5948372
    assert reg.rs2_out.value == 0x1111

    j = 0
    val = 0
    reg_vals = [0, 0xA5948372, 0x1111, 0x1000400, 0x8000000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    for i in range(6, 16):
        reg.rd_in.value = 0
        reg.rd.value = i
        await ClockCycles(reg.clk, 1)
        reg.wr_en.value = 1
        await ClockCycles(reg.clk, 1)
        reg.wr_en.value = 0

    await ClockCycles(reg.clk, 1)

    for i in range(100):
        j = random.randint(0, 15)
        k = random.randint(0, 15)
        val = random.randint(0, 0xFFFFFFFF)

        reg.wr_en.value = 0
        reg.rd_in.value = val
        reg.rd.value = j

        reg.rs1.value = j
        reg.rs2.value = k
        await ClockCycles(reg.clk, 1)
        assert reg.rs1_out.value == reg_vals[j]
        assert reg.rs2_out.value == reg_vals[k]

        reg.wr_en.value = 1
        await ClockCycles(reg.clk, 1)
        if j not in (0, 3, 4): reg_vals[j] = val
        assert reg.rs1_out.value == reg_vals[j]
        assert reg.rs2_out.value == reg_vals[k]
