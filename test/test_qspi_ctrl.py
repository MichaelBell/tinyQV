import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

async def start_read(dut):
    global select

    await ClockCycles(dut.clk, 1, False)
    assert dut.spi_data_oe.value == 0
    assert dut.spi_flash_select.value == 1
    assert dut.spi_ram_a_select.value == 1
    assert dut.spi_ram_b_select.value == 1
    assert dut.spi_clk_out.value == 1

    addr = random.randint(0, (1 << 25) - 1)
    if addr >= 0x1800000:
        select = dut.spi_ram_b_select
    elif addr >= 0x1000000:
        select = dut.spi_ram_a_select
    else:
        select = dut.spi_flash_select

    dut.addr_in.value = addr
    dut.start_read.value = 1
    await ClockCycles(dut.clk, 1, False)
    dut.start_read.value = 0

    assert select.value == 0
    assert dut.spi_flash_select.value == 0 if dut.spi_flash_select == select else 1
    assert dut.spi_ram_a_select.value == 0 if dut.spi_ram_a_select == select else 1
    assert dut.spi_ram_b_select.value == 0 if dut.spi_ram_b_select == select else 1
    assert dut.spi_clk_out.value == 0
    assert dut.spi_data_oe.value == 1

    # Command
    cmd = 0xEB
    for i in range(8):
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_out.value == (1 if cmd & 0x80 else 0)
        assert dut.spi_data_oe.value == 1
        cmd <<= 1
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 0

    # Address
    for i in range(6):
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_out.value == (addr >> (20 - i * 4)) & 0xF
        assert dut.spi_data_oe.value == 0xF
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 0

    # Dummy
    for i in range(2):
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_oe.value == 0xF
        assert dut.spi_data_out.value == 0xF
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 0

    for i in range(4):
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_oe.value == 0
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 0

async def start_write(dut, data):
    global select

    await ClockCycles(dut.clk, 1, False)
    assert dut.spi_data_oe.value == 0
    assert dut.spi_flash_select.value == 1
    assert dut.spi_ram_a_select.value == 1
    assert dut.spi_ram_b_select.value == 1
    assert dut.spi_clk_out.value == 1

    addr = random.randint(1 << 24, (1 << 25) - 1)
    if addr >= 0x1800000:
        select = dut.spi_ram_b_select
    else:
        select = dut.spi_ram_a_select

    dut.addr_in.value = addr
    dut.data_in.value = data
    dut.start_write.value = 1
    await ClockCycles(dut.clk, 1, False)
    dut.start_write.value = 0

    assert select.value == 0
    assert dut.spi_flash_select.value == 1
    assert dut.spi_ram_a_select.value == 0 if dut.spi_ram_a_select == select else 1
    assert dut.spi_ram_b_select.value == 0 if dut.spi_ram_b_select == select else 1
    assert dut.spi_clk_out.value == 0
    assert dut.spi_data_oe.value == 1

    # Command
    cmd = 0x38
    for i in range(8):
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_out.value == (1 if cmd & 0x80 else 0)
        assert dut.spi_data_oe.value == 1
        cmd <<= 1
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 0

    # Address
    for i in range(6):
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_out.value == (addr >> (20 - i * 4)) & 0xF
        assert dut.spi_data_oe.value == 0xF
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 0

async def reset(dut):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2, False)
    dut.rstn.value = 1
    dut.spi_data_in.value = 0
    dut.start_read.value = 0
    dut.start_write.value = 0
    dut.stall_txn.value = 0
    dut.stop_txn.value = 0

@cocotb.test()
async def test_simple_read(dut):
    await reset(dut)

    for k in range(10):
        await start_read(dut)

        # Read
        for j in range(10):
            data = random.randint(0, 255)
            for i in range(2):
                dut.spi_data_in.value = (data >> (4 - i * 4)) & 0xF
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 1
                assert dut.spi_data_oe.value == 0
                assert dut.data_ready.value == 0
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 0
                assert dut.data_ready.value == i

            assert dut.data_out.value == data
            if j == 9:
                dut.stop_txn.value = 1

        for i in range(10):
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_flash_select.value == 1
            assert dut.spi_ram_a_select.value == 1
            assert dut.spi_ram_b_select.value == 1
            assert dut.spi_clk_out.value == 1
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 0
            dut.stop_txn.value = 0

@cocotb.test()
async def test_simple_write(dut):
    await reset(dut)

    for k in range(10):
        data = random.randint(0, 255)
        await start_write(dut, data)

        # Read
        for j in range(10):
            for i in range(2):
                assert dut.spi_data_oe.value == 0xF
                assert dut.spi_data_out.value == (data >> (4 - i * 4)) & 0xF
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 1
                assert dut.spi_data_oe.value == 0xF
                assert dut.spi_data_out.value == (data >> (4 - i * 4)) & 0xF
                assert dut.data_req.value == i
                if i == 1:
                    data = random.randint(0, 255)
                    dut.data_in.value = data

                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 0
                assert dut.data_req.value == 0

            if j == 9:
                dut.stop_txn.value = 1

        # Txn doesn't cancel on low clock
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 1
        assert dut.data_req.value == 0

        for i in range(10):
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_flash_select.value == 1
            assert dut.spi_ram_a_select.value == 1
            assert dut.spi_ram_b_select.value == 1
            assert dut.spi_clk_out.value == 1
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 0
            dut.stop_txn.value = 0

@cocotb.test()
async def test_read_stall(dut):
    await reset(dut)

    for k in range(10):
        await start_read(dut)

        stalled = False
        for j in range(120):
            data = random.randint(0, 255)
            for i in range(2):
                dut.spi_data_in.value = (data >> (4 - i * 4)) & 0xF
                if random.randint(0,15) == 0:
                    stalled = not stalled
                    dut.stall_txn.value = 1 if stalled else 0
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 1
                assert dut.spi_data_oe.value == 0
                assert dut.data_ready.value == 0
                if random.randint(0,15) == 0:
                    stalled = not stalled
                    dut.stall_txn.value = 1 if stalled else 0
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 0
                assert dut.data_ready.value == (0 if stalled else i)

            assert dut.data_out.value == data

            if stalled:
                for i in range(random.randint(1,8)):
                    await ClockCycles(dut.clk, 1, False)
                    assert select.value == 0
                    assert dut.spi_clk_out.value == 0
                    assert dut.spi_data_oe.value == 0
                    assert dut.data_ready.value == 0
                    assert dut.data_out.value == data
                stalled = False
                dut.stall_txn.value = 0
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 0
                assert dut.spi_data_oe.value == 0
                assert dut.data_ready.value == 1
                assert dut.data_out.value == data

        dut.stop_txn.value = 1
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_flash_select.value == 1
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_oe.value == 0
        assert dut.data_ready.value == 0
        dut.stop_txn.value = 0

@cocotb.test()
async def test_stop(dut):
    await reset(dut)

    for j in range(200):
        await start_read(dut)

        data = random.randint(0, 255)
        for i in range(2):
            dut.spi_data_in.value = (data >> (4 - i * 4)) & 0xF
            if random.randint(0,31) == 0:
                dut.stop_txn.value = 1
                break
            await ClockCycles(dut.clk, 1, False)
            assert select.value == 0
            assert dut.spi_clk_out.value == 1
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 0
            if random.randint(0,31) == 0:
                dut.stop_txn.value = 1
                break
            await ClockCycles(dut.clk, 1, False)
            assert select.value == 0
            assert dut.spi_clk_out.value == 0
            assert dut.data_ready.value == i
        else:
            assert dut.data_out.value == data
            dut.stop_txn.value = 1

        for i in range(10):
            await ClockCycles(dut.clk, 1, False)
            dut.stop_txn.value = 0
            assert dut.spi_flash_select.value == 1
            assert dut.spi_ram_a_select.value == 1
            assert dut.spi_ram_b_select.value == 1
            assert dut.spi_clk_out.value == 1
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 0

            

