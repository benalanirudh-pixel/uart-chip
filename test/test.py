# SPDX-License-Identifier: Apache-2.0
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_reset_state(dut):
    """Smoke test: after reset TXD (uo_out[4]) is 1 and the bus is not driven."""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut.ena.value = 1
    dut.ui_in.value = 0x08  # RXD idle high
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    assert (int(dut.uo_out.value) >> 4) & 1 == 1
    assert int(dut.uio_oe.value) == 0
