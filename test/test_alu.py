import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

async def test_op(alu, op):
    clock = Clock(alu.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    alu.rstn.value = 0
    await ClockCycles(alu.clk, 2)
    alu.rstn.value = 1

    a = random.randint(0, 0xFFFFFFFF)
    b = random.randint(0, 0xFFFFFFFF)
    alu.a.value = a
    alu.b.value = b
    await ClockCycles(alu.clk, 1)

    for i in range(100):
        await ClockCycles(alu.clk, 7)
        res = op(a, b) & 0xFFFFFFFF

        a = random.randint(0, 0xFFFFFFFF)
        b = random.randint(0, 0xFFFFFFFF)
        alu.a.value = a
        alu.b.value = b
        await ClockCycles(alu.clk, 1)

        assert alu.d.value == res

@cocotb.test()
async def test_add(alu):
    alu.op.value = 0b0000
    await test_op(alu, lambda a, b: a + b)

@cocotb.test()
async def test_slt(alu):
    clock = Clock(alu.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    alu.rstn.value = 0
    await ClockCycles(alu.clk, 2)
    alu.rstn.value = 1

    alu.op.value = 0b0010

    alu.a.value = 1
    alu.b.value = 1
    await ClockCycles(alu.clk, 8)

    alu.a.value = 0
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 0  # 1 !< 1
    await ClockCycles(alu.clk, 7)

    alu.a.value = 1
    alu.b.value = 0
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 1  # 0 < 1
    await ClockCycles(alu.clk, 7)

    alu.a.value = -1
    alu.b.value = -1
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 0  # 1 !< 0
    await ClockCycles(alu.clk, 7)

    alu.a.value = -2
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 0  # -1 !< -1
    await ClockCycles(alu.clk, 7)

    alu.a.value = 0
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 1  # -2 < -1
    await ClockCycles(alu.clk, 7)

    alu.a.value = 0
    alu.b.value = 0
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 0  # 0 !< -1
    await ClockCycles(alu.clk, 7)

    alu.a.value = -1
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 0  # 0 !< 0
    await ClockCycles(alu.clk, 7)

    a = random.randint(-0x80000000, 0x7FFFFFFF)
    b = random.randint(-0x80000000, 0x7FFFFFFF)
    alu.a.value = a
    alu.b.value = b
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 1  # -1 < 0

    for i in range(100):
        await ClockCycles(alu.clk, 7)
        res = (1 if (a < b) else 0)

        a = random.randint(-0x80000000, 0x7FFFFFFF)
        b = random.randint(-0x80000000, 0x7FFFFFFF)
        alu.a.value = a
        alu.b.value = b
        await ClockCycles(alu.clk, 1)

        assert alu.d.value == res

@cocotb.test()
async def test_sltu(alu):
    clock = Clock(alu.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    alu.rstn.value = 0
    await ClockCycles(alu.clk, 2)
    alu.rstn.value = 1

    alu.op.value = 0b0011

    alu.a.value = 1
    alu.b.value = 1
    await ClockCycles(alu.clk, 8)

    alu.a.value = 0
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 0  # 1 !< 1
    await ClockCycles(alu.clk, 7)

    alu.a.value = -1
    alu.b.value = -1
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 1  # 0 < 1
    await ClockCycles(alu.clk, 7)

    alu.a.value = -2
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 0  # -1 !< -1
    await ClockCycles(alu.clk, 7)

    alu.a.value = 0
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 1  # -2 < -1
    await ClockCycles(alu.clk, 7)

    alu.a.value = 0
    alu.b.value = 0
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 1  # 0 < -1
    await ClockCycles(alu.clk, 7)

    alu.a.value = -1
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 0  # 0 !< 0
    await ClockCycles(alu.clk, 7)

    a = random.randint(0, 0xFFFFFFFF)
    b = random.randint(0, 0xFFFFFFFF)
    alu.a.value = a
    alu.b.value = b
    await ClockCycles(alu.clk, 1)
    assert alu.d.value == 0  # -1 !< 0

    for i in range(100):
        await ClockCycles(alu.clk, 7)
        res = (1 if (a < b) else 0)

        a = random.randint(0, 0xFFFFFFFF)
        b = random.randint(0, 0xFFFFFFFF)
        alu.a.value = a
        alu.b.value = b
        await ClockCycles(alu.clk, 1)

        assert alu.d.value == res

@cocotb.test()
async def test_and(alu):
    alu.op.value = 0b0111
    await test_op(alu, lambda a, b: a & b)

@cocotb.test()
async def test_or(alu):
    alu.op.value = 0b0110
    await test_op(alu, lambda a, b: a | b)

@cocotb.test()
async def test_xor(alu):
    alu.op.value = 0b0100
    await test_op(alu, lambda a, b: a ^ b)

@cocotb.test()
async def test_sub(alu):
    alu.op.value = 0b1000
    await test_op(alu, lambda a, b: a - b)

@cocotb.test()
async def test_eq(alu):
    clock = Clock(alu.clk, 4, units="ns")
    cocotb.start_soon(clock.start())
    alu.rstn.value = 0
    await ClockCycles(alu.clk, 2)
    alu.rstn.value = 1
    alu.op.value = 0b0100

    a = random.randint(0, 0xFFFFFFFF)
    b = random.choice((a, random.randint(0, 0xFFFFFFFF)))
    alu.a.value = a
    alu.b.value = b
    await ClockCycles(alu.clk, 1)

    for i in range(100):
        await ClockCycles(alu.clk, 7)
        res = 1 if (a == b) else 0

        a = random.randint(0, 0xFFFFFFFF)
        b = random.choice((a, random.randint(0, 0xFFFFFFFF)))
        alu.a.value = a
        alu.b.value = b
        await ClockCycles(alu.clk, 1)

        assert alu.cmp.value == res