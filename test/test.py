import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# Protocol of tt_um_wallace_multiplier_serial (24 x 24 -> 48 bit):
#   cycles 1-6  : READ    one byte of ui_in is shifted in per clock (MSB first)
#   cycle  7    : COMPUTE the product is latched (ui_in is ignored)
#   cycles 8-13 : WRITE   the 48-bit result leaves on uo_out, MSB byte first
# The next READ phase starts on the clock edge right after the last WRITE.

N_BYTES = 6


async def tick(dut):
    """Wait for a rising edge, then let the outputs settle (1 us << 5 us half period)."""
    await RisingEdge(dut.clk)
    await Timer(1, unit="us")


async def reset(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    for _ in range(10):
        await tick(dut)
    dut.rst_n.value = 1


async def multiply(dut, a, b):
    """Run one full transaction; return the 48-bit result rebuilt from the six output bytes."""
    # READ: 6 bytes, operand A first then operand B, each MSB first.
    stream = list(a.to_bytes(3, "big")) + list(b.to_bytes(3, "big"))
    for byte in stream:
        dut.ui_in.value = byte
        await tick(dut)

    # COMPUTE: the input must be ignored here, so drive garbage on purpose.
    dut.ui_in.value = 0xAA
    await tick(dut)

    # WRITE: one result byte per clock, MSB first.
    result = 0
    for _ in range(N_BYTES):
        dut.ui_in.value = 0x55  # ignored during WRITE
        await tick(dut)
        result = (result << 8) | int(dut.uo_out.value)
    return result


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # 10 us period (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    dut._log.info("Reset")
    await reset(dut)

    assert int(dut.uio_oe.value) == 0, "uio pins must stay inputs"
    assert int(dut.uio_out.value) == 0

    dut._log.info("Test project behavior")

    vectors = [
        (0x000000, 0x000000),
        (0x000001, 0x000001),
        (0x000002, 0x000003),
        (0xFFFFFF, 0x000001),
        (0xFFFFFF, 0xFFFFFF),  # largest product
        (0x800000, 0x000002),
        (0x123456, 0x789ABC),
        (0xA5A5A5, 0x5A5A5A),
    ]
    rng = random.Random(1234)
    vectors += [(rng.getrandbits(24), rng.getrandbits(24)) for _ in range(20)]

    # Back-to-back transactions: this also checks that the FSM returns to READ cleanly.
    for a, b in vectors:
        got = await multiply(dut, a, b)
        exp = a * b
        dut._log.info(f"{a:#08x} x {b:#08x} = {got:#014x} (expected {exp:#014x})")
        assert got == exp, f"{a:#x} x {b:#x}: got {got:#x}, expected {exp:#x}"


@cocotb.test()
async def test_output_timing(dut):
    """uo_out must stay at 0 through READ and COMPUTE, and carry the MSB byte on WRITE cycle 1."""
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())
    await reset(dut)

    a, b = 0xFFFFFF, 0xFFFFFF  # product 0xFFFFFE000001
    stream = list(a.to_bytes(3, "big")) + list(b.to_bytes(3, "big"))

    for i, byte in enumerate(stream):
        dut.ui_in.value = byte
        await tick(dut)
        assert int(dut.uo_out.value) == 0, f"uo_out changed during READ cycle {i + 1}"

    await tick(dut)  # COMPUTE (7th cycle)
    assert int(dut.uo_out.value) == 0, "uo_out changed during COMPUTE"

    await tick(dut)  # first WRITE cycle
    assert int(dut.uo_out.value) == 0xFF, "first output byte must be the MSB byte"
