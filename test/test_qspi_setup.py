import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

async def setup_flash(dut):
    assert dut.spi_flash_select.value == 0
    assert dut.spi_ram_a_select.value == 1
    assert dut.spi_ram_b_select.value == 1
    assert dut.spi_clk_out.value == 0
    assert dut.spi_data_oe.value == 1

    # Reset
    cmd = 0xFF
    for i in range(8):
        assert dut.spi_data_out.value == (1 if cmd & 0x80 else 0)
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 0
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_out.value == (1 if cmd & 0x80 else 0)
        assert dut.spi_data_oe.value == 1
        cmd <<= 1
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == (0 if i < 7 else 1)
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 0

    for _ in range(2):
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 1
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 0

    await ClockCycles(dut.clk, 1, False)
    assert dut.spi_flash_select.value == 0
    assert dut.spi_ram_a_select.value == 1
    assert dut.spi_ram_b_select.value == 1
    assert dut.spi_clk_out.value == 0
    assert dut.spi_data_oe.value == 1

    # Command
    cmd = 0xEB
    for i in range(8):
        assert dut.spi_data_out.value == (1 if cmd & 0x80 else 0)
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 0
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_out.value == (1 if cmd & 0x80 else 0)
        assert dut.spi_data_oe.value == 1
        cmd <<= 1
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 0
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 0

    # Address
    addr = 0
    for i in range(6):
        assert dut.spi_data_out.value == (addr >> (20 - i * 4)) & 0xF
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 0
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_out.value == (addr >> (20 - i * 4)) & 0xF
        assert dut.spi_data_oe.value == 0xF
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 0
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 0

    # Continuous read
    for i in range(2):
        assert dut.spi_data_out.value == 0xA
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 0
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_oe.value == 0xF
        assert dut.spi_data_out.value == 0xA
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 0
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 0

    for i in range(8):
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 0
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_oe.value == 0
        if i == 7:
            break
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 0
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_data_oe.value == 0
        assert dut.spi_clk_out.value == 0

async def setup_ram(dut, ram_a):
    assert dut.spi_flash_select.value == 1
    assert dut.spi_ram_a_select.value == (0 if ram_a else 1)
    assert dut.spi_ram_b_select.value == (1 if ram_a else 0)
    assert dut.spi_clk_out.value == 0
    assert dut.spi_data_oe.value == 1

    # Command
    cmd = 0x35
    for i in range(8):
        assert dut.spi_data_out.value == (1 if cmd & 0x80 else 0)
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 1
        assert dut.spi_ram_a_select.value == (0 if ram_a else 1)
        assert dut.spi_ram_b_select.value == (1 if ram_a else 0)
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_out.value == (1 if cmd & 0x80 else 0)
        assert dut.spi_data_oe.value == 1
        cmd <<= 1
        if i == 7:
            break
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 1
        assert dut.spi_ram_a_select.value == (0 if ram_a else 1)
        assert dut.spi_ram_b_select.value == (1 if ram_a else 0)
        assert dut.spi_clk_out.value == 0

@cocotb.test()
async def test_setup(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2, False)
    dut.rstn.value = 1
    assert dut.done.value == 0
    assert dut.spi_flash_select.value == 1
    assert dut.spi_ram_a_select.value == 1
    assert dut.spi_ram_b_select.value == 1
    await ClockCycles(dut.clk, 1, False)

    await setup_flash(dut)
    assert dut.done.value == 0
    await ClockCycles(dut.clk, 1, False)
    assert dut.done.value == 0
    await setup_ram(dut, True)
    assert dut.done.value == 0
    await ClockCycles(dut.clk, 1, False)
    assert dut.done.value == 0
    await setup_ram(dut, False)
    assert dut.done.value == 0
    await ClockCycles(dut.clk, 1, False)
    assert dut.done.value == 1
