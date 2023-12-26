import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

async def start_read(dut):
    await ClockCycles(dut.clk, 1, False)
    assert dut.spi_data_oe.value == 0
    assert dut.spi_select.value == 1
    assert dut.spi_clk_out.value == 1

    addr = random.randint(0, 1 << 20)
    dut.addr_in.value = addr
    dut.start_read.value = 1
    await ClockCycles(dut.clk, 1, False)
    dut.start_read.value = 0

    assert dut.spi_select.value == 0
    assert dut.spi_clk_out.value == 0
    assert dut.spi_data_oe.value == 1

    # Command
    cmd = 0xEB
    for i in range(8):
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_select.value == 0
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_out.value == (1 if cmd & 0x80 else 0)
        assert dut.spi_data_oe.value == 1
        cmd <<= 1
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_select.value == 0
        assert dut.spi_clk_out.value == 0

    # Address
    for i in range(6):
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_select.value == 0
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_out.value == (addr >> (20 - i * 4)) & 0xF
        assert dut.spi_data_oe.value == 0xF
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_select.value == 0
        assert dut.spi_clk_out.value == 0

    # Dummy
    for i in range(2):
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_select.value == 0
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_oe.value == 0xF
        assert dut.spi_data_out.value == 0xF
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_select.value == 0
        assert dut.spi_clk_out.value == 0

    for i in range(4):
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_select.value == 0
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_oe.value == 0
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_select.value == 0
        assert dut.spi_clk_out.value == 0

async def reset_and_start_read(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2, False)
    dut.rstn.value = 1
    dut.spi_data_in.value = 0
    dut.start_read.value = 0
    dut.stall_read.value = 0
    dut.stop_read.value = 0

    await start_read(dut)

@cocotb.test()
async def test_simple_read(dut):
    await reset_and_start_read(dut)

    # Read
    for j in range(10):
        data = random.randint(0, 65535)
        for i in range(4):
            dut.spi_data_in.value = (data >> (12 - i * 4)) & 0xF
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_select.value == 0
            assert dut.spi_clk_out.value == 1
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 0
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_select.value == 0
            assert dut.spi_clk_out.value == 0
            assert dut.data_ready.value == (1 if i == 3 else 0)

        assert dut.data_out.value == data
        if j == 9:
            dut.stop_read.value = 1

    for i in range(10):
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_select.value == 1
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_oe.value == 0
        assert dut.data_ready.value == 0
    
@cocotb.test()
async def test_stall(dut):
    await reset_and_start_read(dut)

    stalled = False
    for j in range(400):
        data = random.randint(0, 65535)
        for i in range(4):
            dut.spi_data_in.value = (data >> (12 - i * 4)) & 0xF
            if random.randint(0,31) == 0:
                stalled = not stalled
                dut.stall_read.value = 1 if stalled else 0
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_select.value == 0
            assert dut.spi_clk_out.value == 1
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 0
            if random.randint(0,31) == 0:
                stalled = not stalled
                dut.stall_read.value = 1 if stalled else 0
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_select.value == 0
            assert dut.spi_clk_out.value == 0
            assert dut.data_ready.value == (1 if i == 3 else 0)

        assert dut.data_out.value == data

        if stalled:
            for i in range(random.randint(1,8)):
                await ClockCycles(dut.clk, 1, False)
                assert dut.spi_select.value == 0
                assert dut.spi_clk_out.value == 0
                assert dut.spi_data_oe.value == 0
                assert dut.data_ready.value == 1
                assert dut.data_out.value == data
            stalled = False
            dut.stall_read.value = 0
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_select.value == 0
            assert dut.spi_clk_out.value == 0
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 1
            assert dut.data_out.value == data

@cocotb.test()
async def test_stop(dut):
    await reset_and_start_read(dut)

    for j in range(100):
        data = random.randint(0, 65535)
        for i in range(4):
            dut.spi_data_in.value = (data >> (12 - i * 4)) & 0xF
            if random.randint(0,31) == 0:
                dut.stop_read.value = 1
                break
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_select.value == 0
            assert dut.spi_clk_out.value == 1
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 0
            if random.randint(0,31) == 0:
                dut.stop_read.value = 1
                break
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_select.value == 0
            assert dut.spi_clk_out.value == 0
            assert dut.data_ready.value == (1 if i == 3 else 0)
        else:
            assert dut.data_out.value == data
            dut.stop_read.value = 1

        for i in range(10):
            await ClockCycles(dut.clk, 1, False)
            dut.stop_read.value = 0
            assert dut.spi_select.value == 1
            assert dut.spi_clk_out.value == 1
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 0

        await start_read(dut)

