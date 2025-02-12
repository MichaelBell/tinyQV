import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

select = None

async def start_read(dut, clock_delay = False):
    global select

    await ClockCycles(dut.clk, 1, False)
    assert dut.spi_data_oe.value == 0
    assert dut.spi_flash_select.value == 1
    assert dut.spi_ram_a_select.value == 1
    assert dut.spi_ram_b_select.value == 1
    assert dut.spi_clk_out.value == 0

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
    assert dut.spi_flash_select.value == (0 if dut.spi_flash_select == select else 1)
    assert dut.spi_ram_a_select.value == (0 if dut.spi_ram_a_select == select else 1)
    assert dut.spi_ram_b_select.value == (0 if dut.spi_ram_b_select == select else 1)
    assert dut.spi_clk_out.value == 0

    if dut.spi_flash_select != select:
        # Command
        cmd = 0x0B
        assert dut.spi_data_oe.value == 0xF
        for i in range(2):
            await ClockCycles(dut.clk, 1, False)
            assert select.value == 0
            assert dut.spi_data_out.value == (cmd & 0xF0) >> 4
            assert dut.spi_data_oe.value == 0xF
            cmd <<= 4
            if clock_delay:
                assert dut.spi_clk_out.value == 0
                await ClockCycles(dut.clk, 1, True)
            assert dut.spi_clk_out.value == 1

            await ClockCycles(dut.clk, 1, False)
            assert select.value == 0
            if clock_delay:
                assert dut.spi_clk_out.value == 1
                await ClockCycles(dut.clk, 1, True)
            assert dut.spi_clk_out.value == 0

    # Address
    assert dut.spi_data_oe.value == 0xF
    for i in range(6):
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_data_out.value == (addr >> (20 - i * 4)) & 0xF
        assert dut.spi_data_oe.value == 0xF
        if clock_delay:
            assert dut.spi_clk_out.value == 0
            await ClockCycles(dut.clk, 1, True)
        assert dut.spi_clk_out.value == 1

        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        if clock_delay:
            assert dut.spi_clk_out.value == 1
            await ClockCycles(dut.clk, 1, True)
        assert dut.spi_clk_out.value == 0

    # Dummy
    if dut.spi_flash_select == select:
        for i in range(2):
            await ClockCycles(dut.clk, 1, False)
            assert select.value == 0
            assert dut.spi_data_oe.value == 0xF
            assert dut.spi_data_out.value == 0xA
            if clock_delay:
                assert dut.spi_clk_out.value == 0
                await ClockCycles(dut.clk, 1, True)
            assert dut.spi_clk_out.value == 1
            await ClockCycles(dut.clk, 1, False)
            assert select.value == 0
            if clock_delay:
                assert dut.spi_clk_out.value == 1
                await ClockCycles(dut.clk, 1, True)
            assert dut.spi_clk_out.value == 0

    for i in range(4):
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        if clock_delay:
            assert dut.spi_clk_out.value == 0
            await ClockCycles(dut.clk, 1, True)
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_oe.value == 0
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        if i != 3:
            if clock_delay:
                assert dut.spi_clk_out.value == 1
                await ClockCycles(dut.clk, 1, True)
            assert dut.spi_clk_out.value == 0
        elif not clock_delay:
            assert dut.spi_clk_out.value == 0

async def start_write(dut, data):
    global select

    await ClockCycles(dut.clk, 1, False)
    assert dut.spi_data_oe.value == 0
    assert dut.spi_flash_select.value == 1
    assert dut.spi_ram_a_select.value == 1
    assert dut.spi_ram_b_select.value == 1
    assert dut.spi_clk_out.value == 0

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
    assert dut.spi_ram_a_select.value == (0 if dut.spi_ram_a_select == select else 1)
    assert dut.spi_ram_b_select.value == (0 if dut.spi_ram_b_select == select else 1)
    assert dut.spi_clk_out.value == 0
    assert dut.spi_data_oe.value == 0xF

    # Command
    cmd = 0x02
    for i in range(2):
        await ClockCycles(dut.clk, 1, False)
        assert select.value == 0
        assert dut.spi_clk_out.value == 1
        assert dut.spi_data_out.value == (cmd & 0xF0) >> 4
        assert dut.spi_data_oe.value == 0xF
        cmd <<= 4
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

async def reset(dut, latency=0):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 0
    dut.spi_data_in.value = latency
    await ClockCycles(dut.clk, 2, False)
    dut.rstn.value = 1
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
                assert dut.data_ready.value == i
                if i == 1: assert dut.data_out.value == data
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 0
                assert dut.data_ready.value == 0

            if j == 9:
                dut.stop_txn.value = 1

        for i in range(10):
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_flash_select.value == 1
            assert dut.spi_ram_a_select.value == 1
            assert dut.spi_ram_b_select.value == 1
            assert dut.spi_clk_out.value == 0
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
            assert dut.spi_clk_out.value == 0
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 0
            dut.stop_txn.value = 0

@cocotb.test()
async def test_read_stall(dut):
    for latency in range(0,2):
        await reset(dut, latency)

        for k in range(10):
            await start_read(dut)

            stalled = False
            for j in range(120):
                data = random.randint(0, 255)
                for i in range(4):
                    if (i & 1) == 0:
                        dut.spi_data_in.value = (data >> (4 - (i & 2) * 2)) & 0xF
                    if random.randint(0,15) == 0:
                        stalled = True
                        dut.stall_txn.value = 1 if stalled else 0
                    await ClockCycles(dut.clk, 1, False)
                    assert select.value == 0
                    assert dut.spi_clk_out.value == (1 if i & 1 == 0 else 0)
                    assert dut.spi_data_oe.value == 0
                    assert dut.data_ready.value == (0 if i != 2 + latency or stalled else 1)
                    if i == 2 + latency:
                        assert dut.data_out.value == data
                        if stalled:
                            assert dut.data_ready.value == 0
                            for j in range(random.randint(1,8)):
                                await ClockCycles(dut.clk, 1, False)
                                assert select.value == 0
                                assert dut.spi_clk_out.value == 0
                                assert dut.spi_data_oe.value == 0
                                assert dut.data_ready.value == 0
                            stalled = False
                            dut.stall_txn.value = 0
                            await ClockCycles(dut.clk, 1, False)
                            assert select.value == 0
                            assert dut.spi_clk_out.value == 0
                            assert dut.spi_data_oe.value == 0
                            break

            dut.stall_txn.value = 0
            dut.stop_txn.value = 1
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_flash_select.value == 1
            assert dut.spi_ram_a_select.value == 1
            assert dut.spi_ram_b_select.value == 1
            assert dut.spi_clk_out.value == 0
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 0
            dut.stop_txn.value = 0

@cocotb.test()
async def test_stop(dut):
    for latency in range(0,2):
        await reset(dut, latency)

        for j in range(100):
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
                if i == 1 and latency == 0:
                    assert dut.data_ready.value == 1
                    assert dut.data_out.value == data
                else:
                    assert dut.data_ready.value == 0
                if random.randint(0,31) == 0:
                    dut.stop_txn.value = 1
                    break
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 0
                if i == 1 and latency == 1:
                    assert dut.data_ready.value == 1
                    assert dut.data_out.value == data
                else:
                    assert dut.data_ready.value == 0
            else:
                dut.stop_txn.value = 1

            for i in range(10):
                await ClockCycles(dut.clk, 1, False)
                dut.stop_txn.value = 0
                assert dut.spi_flash_select.value == 1
                assert dut.spi_ram_a_select.value == 1
                assert dut.spi_ram_b_select.value == 1
                assert dut.spi_clk_out.value == 0
                assert dut.spi_data_oe.value == 0
                assert dut.data_ready.value == 0

@cocotb.test()
async def test_clock_delay(dut):
    await reset(dut, 4)

    for k in range(10):
        await start_read(dut, True)

        # Read
        for j in range(10):
            data = random.randint(0, 255)
            for i in range(2):
                dut.spi_data_in.value = (data >> (4 - i * 4)) & 0xF
                await ClockCycles(dut.clk, 1, True)
                assert dut.spi_clk_out.value == 0
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 0
                assert dut.spi_data_oe.value == 0
                assert dut.data_ready.value == i
                if i == 1: assert dut.data_out.value == data
                await ClockCycles(dut.clk, 1, True)
                assert dut.spi_clk_out.value == 1
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 1
                assert dut.data_ready.value == 0

            if j == 9:
                dut.stop_txn.value = 1

        for i in range(10):
            await ClockCycles(dut.clk, 1, True)
            assert dut.spi_clk_out.value == 0
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_flash_select.value == 1
            assert dut.spi_ram_a_select.value == 1
            assert dut.spi_ram_b_select.value == 1
            assert dut.spi_clk_out.value == 0
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 0
            dut.stop_txn.value = 0

# TODO: This test is mostly nonsense
@cocotb.test()
async def test_latency(dut):
    for latency in range(1, 4):
        await reset(dut, latency)

        for k in range(3):
            await start_read(dut)

            # Latency
            await ClockCycles(dut.clk, latency, False)

            # Read
            for j in range(4):
                data = random.randint(0, 255)
                for i in range(2):
                    dut.spi_data_in.value = (data >> (4 - i * 4)) & 0xF
                    await ClockCycles(dut.clk, 1, False)
                    assert select.value == 0
                    assert dut.spi_clk_out.value == (1 + latency) & 1
                    assert dut.spi_data_oe.value == 0
                    if i == 1 and j == 3:
                        break
                    assert dut.data_ready.value == i
                    if i == 1: assert dut.data_out.value == data
                    await ClockCycles(dut.clk, 1, False)
                    assert select.value == 0
                    assert dut.spi_clk_out.value == (0 + latency) & 1
                    assert dut.data_ready.value == 0
                if j == 2:
                    dut.stall_txn.value = 1
            
            data0 = data
            for i in range(-1, latency-1):
                if (i & 3) == 0: 
                    data = random.randint(0, 255)
                if (i & 1) == 0: 
                    dut.spi_data_in.value = (data >> (4 - (i & 2) * 2)) & 0xF
                    await ClockCycles(dut.clk, 1, False)
                    assert select.value == 0
                    assert dut.spi_clk_out.value == 0
                    assert dut.spi_data_oe.value == 0
                    assert dut.data_ready.value == 0
                else:
                    await ClockCycles(dut.clk, 1, False)
                    assert select.value == 0
                    assert dut.spi_clk_out.value == 0
                    assert dut.spi_data_oe.value == 0
                    assert dut.data_ready.value == 0

            await ClockCycles(dut.clk, 5, False)
            dut.stall_txn.value = 0
            await ClockCycles(dut.clk, 1, False)
            assert dut.spi_clk_out.value == 0
            assert dut.data_ready.value == 1
            assert dut.data_out.value == data0
            for i in range(latency):
                await ClockCycles(dut.clk, 1, False)
                if latency >= 4 and i == latency - 2:
                    assert dut.data_ready.value == 1
                    assert dut.data_out.value == data
                    data = random.randint(0, 255)                    
                else:
                    assert dut.data_ready.value == 0
                assert dut.spi_clk_out.value == (1 if i & 1 == 0 else 0)

            for i in range(latency, 20):
                if (i & 3) == 0:
                    data = random.randint(0, 255)
                if (i & 1) == 0:
                    if (latency & 1) == 0:
                        dut.spi_data_in.value = (data >> (4 - (i & 2) * 2)) & 0xF
                    await ClockCycles(dut.clk, 1, False)
                    assert select.value == 0
                    assert dut.spi_clk_out.value == 1
                    assert dut.spi_data_oe.value == 0
                else:
                    if (latency & 1) == 1:
                        dut.spi_data_in.value = (data >> (4 - (i & 2) * 2)) & 0xF
                    await ClockCycles(dut.clk, 1, False)
                    assert select.value == 0
                    assert dut.spi_clk_out.value == 0
                    assert dut.spi_data_oe.value == 0
                if i & 3 == [3, 3, 2, 3, 2, 3][latency]:
                    assert dut.data_ready.value == 1
                    assert dut.data_out.value == data
                else:
                    assert dut.data_ready.value == 0

            dut.stop_txn.value = 1

            for i in range(10):
                await ClockCycles(dut.clk, 1, False)
                assert dut.spi_flash_select.value == 1
                assert dut.spi_ram_a_select.value == 1
                assert dut.spi_ram_b_select.value == 1
                assert dut.spi_clk_out.value == 0
                assert dut.spi_data_oe.value == 0
                assert dut.data_ready.value == 0
                dut.stop_txn.value = 0            
