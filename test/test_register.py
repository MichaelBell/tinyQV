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
    reg.wr_en.value = 1
    #await ClockCycles(reg.clk, 1)

    reg.rs1.value = 1
    reg.rs2.value = 2
    reg.rd.value = 1

    reg.rd_in.value = 0x12345679
    await ClockCycles(reg.clk, 8)

    reg.wr_en.value = 0
    await ClockCycles(reg.clk, 8)

    reg.wr_en.value = 1
    reg.rd_in.value = 0xA5948372
    await ClockCycles(reg.clk, 1)
    assert reg.rs1_out.value == 0x12345679
    await ClockCycles(reg.clk, 7)

    reg.wr_en.value = 1
    reg.rd.value = 5
    reg.rd_in.value = 0
    await ClockCycles(reg.clk, 8)
    reg.rd.value = 2
    reg.rs1.value = 5
    await ClockCycles(reg.clk, 1)
    assert reg.rs1_out.value == 0xA5948372

    await ClockCycles(reg.clk, 7)
    reg.rd.value = 0
    reg.rs1.value = 1
    await ClockCycles(reg.clk, 1)
    assert reg.rs1_out.value == 0
    await ClockCycles(reg.clk, 7)
    reg.rs1.value = 0
    await ClockCycles(reg.clk, 1)
    assert reg.rs1_out.value == 0xA5948372

    await ClockCycles(reg.clk, 7)

    j = 0
    val = 0
    reg_vals = [0, 0xA5948372, 0, 0x1000400, 0x8000000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    for i in range(6, 16):
        reg.rd.value = i
        await ClockCycles(reg.clk, 8)

    await ClockCycles(reg.clk, 1)

    for i in range(100):
        await ClockCycles(reg.clk, 7)

        reg.rs1.value = j
        reg.wr_en.value = 0
        await ClockCycles(reg.clk, 8)

        last_val = val
        last_j = j
        if last_j == 0: last_val = 0
        elif last_j == 3: last_val = 0x1000400
        elif last_j == 4: last_val = 0x8000000
        else: reg_vals[last_j] = last_val
        val = random.randint(0, 0xFFFFFFFF)
        j = random.randint(0, 15)

        reg.wr_en.value = 1
        reg.rd_in.value = val
        reg.rd.value = j

        await ClockCycles(reg.clk, 1)
        assert reg.rs1_out.value == (0 if last_j == 0 else last_val)

    await ClockCycles(reg.clk, 7)
    reg.wr_en.value = 0
    last_val = val
    last_j = j
    if last_j == 0: last_val = 0
    elif last_j == 3: last_val = 0x1000400
    elif last_j == 4: last_val = 0x8000000
    else: reg_vals[last_j] = last_val

    reg.rs1.value = 0
    await ClockCycles(reg.clk, 1)

    for i in range(16):
        await ClockCycles(reg.clk, 7)
        reg.rs1.value = (i+1) & 0xF
        await ClockCycles(reg.clk, 1)
        assert reg.rs1_out.value == reg_vals[i]

    await ClockCycles(reg.clk, 7)
    reg.wr_en.value = 1
    reg.rd.value = 0
    reg.rs1.value = 0
    reg.rs2.value = 0
    rd = 0
    rs1 = 0
    rs2 = 0
    val = 0
    await ClockCycles(reg.clk, 1)

    for i in range(100):
        await ClockCycles(reg.clk, 7)

        last_val = val
        last_rd = rd
        last_rs1 = rs1
        last_rs2 = rs2

        val = random.randint(0, 0xFFFFFFFF)
        rs1 = random.randint(0, 15)
        rs2 = random.randint(0, 15)
        rd = random.randint(0, 15)

        reg.rs1.value = rs1
        reg.rs2.value = rs2
        reg.rd.value = rd
        reg.rd_in.value = val
        await ClockCycles(reg.clk, 1)
        assert reg.rs1_out.value == reg_vals[last_rs1]
        assert reg.rs2_out.value == reg_vals[last_rs2]
        if last_rd not in (0, 3, 4): reg_vals[last_rd] = last_val
