import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles
from cocotb.binary import BinaryValue

select = None

async def start_data_read(dut, len_code, read_follows_read, data_continue=False):
    global select

    await ClockCycles(dut.clk, 1, False)
    assert dut.spi_data_oe.value == 0
    assert dut.spi_flash_select.value == 1
    assert dut.spi_ram_a_select.value == 1
    assert dut.spi_ram_b_select.value == 1
    assert dut.spi_clk_out.value == 0

    addr = random.randint(0, (1 << 25) - 1)
    last_select = select
    if addr >= 0x1800000:
        select = dut.spi_ram_b_select
    elif addr >= 0x1000000:
        select = dut.spi_ram_a_select
    else:
        select = dut.spi_flash_select

    dut.data_addr.value = addr
    dut.data_read_n.value = len_code
    dut.data_continue.value = (1 if data_continue else 0)
    await ClockCycles(dut.clk, 1, False)

    if read_follows_read and last_select == select and select != dut.spi_flash_select:
        assert dut.spi_data_oe.value == 0
        assert dut.spi_flash_select.value == 1
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 0
        await ClockCycles(dut.clk, 1, False)     

    assert select.value == 0
    assert dut.spi_flash_select.value == 0 if dut.spi_flash_select == select else 1
    assert dut.spi_ram_a_select.value == 0 if dut.spi_ram_a_select == select else 1
    assert dut.spi_ram_b_select.value == 0 if dut.spi_ram_b_select == select else 1
    assert dut.spi_clk_out.value == 0

    if dut.spi_flash_select != select:
        # Command
        cmd = 0x0B
        assert dut.spi_data_oe.value == 0xF
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
    assert dut.spi_data_oe.value == 0xF
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
    if dut.spi_flash_select == select:
        for i in range(2):
            await ClockCycles(dut.clk, 1, False)
            assert select.value == 0
            assert dut.spi_clk_out.value == 1
            assert dut.spi_data_oe.value == 0xF
            assert dut.spi_data_out.value == 0xA
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

async def start_data_write(dut, data, len_code, delay_start, data_continue=False):
    global select

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

    dut.data_addr.value = addr
    dut.data_to_write.value = data
    dut.data_write_n.value = len_code
    dut.data_continue.value = (1 if data_continue else 0)
    if delay_start:
        await ClockCycles(dut.clk, 1, False)
        assert dut.spi_data_oe.value == 0
        assert dut.spi_flash_select.value == 1
        assert dut.spi_ram_a_select.value == 1
        assert dut.spi_ram_b_select.value == 1
        assert dut.spi_clk_out.value == 0
    await ClockCycles(dut.clk, 1, True)
    assert dut.data_ready.value == 1
    dut.data_write_n.value = 3
    await ClockCycles(dut.clk, 1, False)

    assert select.value == 0
    assert dut.spi_flash_select.value == 1
    assert dut.spi_ram_a_select.value == 0 if dut.spi_ram_a_select == select else 1
    assert dut.spi_ram_b_select.value == 0 if dut.spi_ram_b_select == select else 1
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

async def reset(dut, latency=1):
    clock = Clock(dut.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    dut.rstn.value = 1
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 0
    dut.spi_data_in.value = latency
    await ClockCycles(dut.clk, 3, False)
    dut.rstn.value = 1
    dut.spi_data_in.value = 0
    dut.instr_fetch_restart.value = 0
    dut.instr_fetch_stall.value = 0
    dut.data_write_n.value = 3
    dut.data_read_n.value = 3
    dut.data_continue.value = 0
    await ClockCycles(dut.clk, 1, False)

nibble_shift_order = [4, 0, 12, 8, 20, 16, 28, 24]

@cocotb.test()
async def test_data_read(dut):
    await reset(dut)

    for k in range(100):
        len_code = random.randint(0, 2)
        read_len = [1, 2, 4][len_code]
        
        await start_data_read(dut, len_code, k != 0)

        # Read
        data = random.randint(0, (1 << (8 * read_len)) - 1)
        for i in range(2 * read_len):
            dut.spi_data_in.value = (data >> (nibble_shift_order[i])) & 0xF
            await ClockCycles(dut.clk, 1, False)
            assert select.value == 0
            assert dut.spi_clk_out.value == 1
            assert dut.spi_data_oe.value == 0
            assert dut.data_ready.value == 0
            await ClockCycles(dut.clk, 1, False)
            assert select.value == 0
            assert dut.spi_clk_out.value == 0
            assert dut.data_ready.value == (1 if i == 2 * read_len - 1 else 0)

        # Need to only read the valid bits
        bits_out = dut.data_from_read.value.binstr
        bits_out = bits_out[32 - 8 * read_len:]
        format_str = "{:" + "0{}b".format(8 * read_len) + "}"
        assert bits_out == format_str.format(data)

@cocotb.test()
async def test_data_write(dut):
    await reset(dut)

    delay = False
    for k in range(50):
        len_code = random.randint(0, 2)
        read_len = [1, 2, 4][len_code]        
        data = random.randint(0, (1 << (8 * read_len)) - 1)
        await start_data_write(dut, data, len_code, delay)

        # Write
        for i in range(2 * read_len):
            assert dut.spi_data_oe.value == 0xF
            assert dut.spi_data_out.value == (data >> (nibble_shift_order[i])) & 0xF
            await ClockCycles(dut.clk, 1, False)
            assert select.value == 0
            assert dut.spi_clk_out.value == 1
            assert dut.spi_data_oe.value == 0xF
            assert dut.spi_data_out.value == (data >> (nibble_shift_order[i])) & 0xF
            assert dut.data_ready.value == 0
            await ClockCycles(dut.clk, 1, False)
            if i == 2 * read_len - 1:
                assert select.value == 1
                assert dut.spi_clk_out.value == 0
                assert dut.data_ready.value == 0
            else:
                assert select.value == 0
                assert dut.spi_clk_out.value == 0
                assert dut.data_ready.value == 0

        if random.randint(0, 1) == 1:
            await ClockCycles(dut.clk, 1, False)
            delay = False
        else:
            delay = True

@cocotb.test()
async def test_data_read_continue(dut):
    await reset(dut)

    for k in range(20):
        len_code = 2
        read_len = 4
        num_reads = random.randint(2, 16)
        
        await start_data_read(dut, len_code, k != 0, True)

        for j in range(num_reads):
            
            data = random.randint(0, (1 << (8 * read_len)) - 1)
            for i in range(2 * read_len):
                dut.spi_data_in.value = (data >> (nibble_shift_order[i])) & 0xF
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 1
                assert dut.spi_data_oe.value == 0
                assert dut.data_ready.value == 0
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 0
                if j != 0 and i == 1:
                    assert dut.data_ready.value == 0
                    await ClockCycles(dut.clk, random.randint(1,8), False)
                    assert select.value == 0
                    assert dut.spi_clk_out.value == 0
                    dut.data_read_n.value = len_code
                    dut.data_continue.value = (1 if j != num_reads - 1 else 0)
                    await ClockCycles(dut.clk, 2, False)
                    assert select.value == 0
                    assert dut.spi_clk_out.value == 0
                else:
                    assert dut.data_ready.value == (1 if i == 2 * read_len - 1 else 0)

            assert dut.data_from_read.value == data
            dut.data_read_n.value = 3

@cocotb.test()
async def test_data_write_continue(dut):
    await reset(dut)

    len_code = 2
    read_len = 4
    for k in range(20):
        num_writes = random.randint(2, 16)
        
        data = random.randint(0, (1 << (8 * read_len)) - 1)
        await start_data_write(dut, data, len_code, False, True)

        # New data ready after QSPI transaction completes
        for j in range(num_writes):
            for i in range(2 * read_len):
                assert dut.spi_data_oe.value == 0xF
                assert dut.spi_data_out.value == (data >> (nibble_shift_order[i])) & 0xF
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 1
                assert dut.spi_data_oe.value == 0xF
                assert dut.spi_data_out.value == (data >> (nibble_shift_order[i])) & 0xF
                assert dut.data_ready.value == 0
                await ClockCycles(dut.clk, 1, False)
                if i != 2 * read_len - 1:
                    assert select.value == 0
                    assert dut.spi_clk_out.value == 0
                    assert dut.data_ready.value == 0

            assert dut.spi_clk_out.value == 0
            assert dut.data_ready.value == 0
            if j != num_writes - 1:
                assert select.value == 0
                data = random.randint(0, (1 << (8 * read_len)) - 1)
                await ClockCycles(dut.clk, random.randint(1,8), False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 0
                dut.data_write_n.value = len_code
                dut.data_to_write.value = data
                dut.data_continue.value = (1 if j != num_writes - 2 else 0)
                await ClockCycles(dut.clk, 1)
                assert dut.data_ready.value == 1
                dut.data_write_n.value = 3
                await ClockCycles(dut.clk, 2, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 0
            else:
                assert select.value == 1
        
        await ClockCycles(dut.clk, random.randint(1,8), False)

        num_writes = random.randint(2, 8)
        
        data = random.randint(0, (1 << (8 * read_len)) - 1)
        await start_data_write(dut, data, len_code, False, True)

        # New data ready almost immediately
        for j in range(num_writes):
            for i in range(2 * read_len):
                assert dut.spi_data_oe.value == 0xF
                assert dut.spi_data_out.value == (data >> (nibble_shift_order[i])) & 0xF
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 1
                assert dut.spi_data_oe.value == 0xF
                assert dut.spi_data_out.value == (data >> (nibble_shift_order[i])) & 0xF
                assert dut.data_ready.value == 0
                await ClockCycles(dut.clk, 1, False)
                if i == 0 and j != num_writes - 1:
                    next_data = random.randint(0, (1 << (8 * read_len)) - 1)
                    dut.data_write_n.value = len_code
                    dut.data_to_write.value = next_data
                    dut.data_continue.value = (1 if j != num_writes - 2 else 0)
                if i != 2 * read_len - 1:
                    assert select.value == 0
                    assert dut.spi_clk_out.value == 0
                    assert dut.data_ready.value == 0

            await ClockCycles(dut.clk, 1)
            assert dut.spi_clk_out.value == 0
            if j != num_writes - 1:
                assert dut.data_ready.value == 1
                dut.data_write_n.value = 3
                assert select.value == 0
                data = next_data
                await ClockCycles(dut.clk, 2, False)
                assert select.value == 0
                assert dut.spi_clk_out.value == 0
            else:
                await ClockCycles(dut.clk, 1, False)
                assert select.value == 1
        
        await ClockCycles(dut.clk, random.randint(1,8), False)
