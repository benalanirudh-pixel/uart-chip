# SPDX-License-Identifier: Apache-2.0
# cocotb tests for tt_um_anirudh_uart. See docs/spec.md for the pin map.
#
# Pins:  ui_in: [0]=WR [1]=RD [3]=RXD [5:4]=ADDR      uio = 8-bit data bus
#        uo_out: [0]=RX_AVAIL [1]=TX_READY [2]=OVERRUN [3]=FRAME_ERR [4]=TXD
#                [5]=TX_BUSY [6]=RX_FULL

import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Lock, RisingEdge

DATA, STATUS, DIV_LO, DIV_HI = 0, 1, 2, 3
SIM_DIV = 4  # small divider keeps simulations short (default hardware value is 27)
LONG = dict(timeout_time=500, timeout_unit="ms")


class Env:
    """Owns the input pins: bus strobes, address and RXD share ui_in."""

    def __init__(self, dut):
        self.dut = dut
        self.rxd, self.wr, self.rd, self.addr = 1, 0, 0, 0
        self.lock = Lock()  # only one coroutine may use the host bus at a time

    def _ui(self):
        self.dut.ui_in.value = (self.addr << 4) | (self.rxd << 3) | (self.rd << 1) | self.wr

    def set_rxd(self, v):
        self.rxd = v
        self._ui()

    async def cycles(self, n):
        await ClockCycles(self.dut.clk, n)

    async def write(self, addr, data):
        async with self.lock:
            self.addr = addr
            self.dut.uio_in.value = data
            self._ui()
            await self.cycles(5)
            self.wr = 1
            self._ui()
            await self.cycles(5)
            self.wr = 0
            self._ui()
            await self.cycles(5)

    async def read(self, addr):
        async with self.lock:
            self.addr = addr
            self._ui()
            await self.cycles(5)
            self.rd = 1
            self._ui()
            await self.cycles(8)
            assert int(self.dut.uio_oe.value) == 0xFF, "chip must drive the bus during a read"
            val = int(self.dut.uio_out.value)
            self.rd = 0
            self._ui()
            await self.cycles(5)
            return val

    def pin(self, n):
        return (int(self.dut.uo_out.value) >> n) & 1

    async def set_div(self, div):
        await self.write(DIV_LO, div & 0xFF)
        await self.write(DIV_HI, div >> 8)


async def setup(dut, div=SIM_DIV):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())  # 50 MHz
    env = Env(dut)
    dut.ena.value = 1
    dut.uio_in.value = 0
    env.set_rxd(1)
    dut.rst_n.value = 0
    await env.cycles(10)
    dut.rst_n.value = 1
    await env.cycles(5)
    if div is not None:
        await env.set_div(div)
    return env


async def loopback(env):
    """Testbench wire: TXD (uo_out[4]) -> RXD (ui_in[3])."""
    while True:
        await RisingEdge(env.dut.clk)
        v = env.pin(4)
        if v != env.rxd:
            env.set_rxd(v)


async def tx_frame(env, div):
    """Wait for a start bit on TXD, record one frame. Returns (byte, stop_ok, edge_times)."""
    while env.pin(4):
        await RisingEdge(env.dut.clk)
    bit = 16 * div
    lv = []
    for _ in range(10 * bit):
        lv.append(env.pin(4))
        await RisingEdge(env.dut.clk)
    bits = [lv[int(bit * (k + 0.5))] for k in range(10)]  # sample mid-bit
    assert bits[0] == 0, "start bit must be 0"
    byte = sum(bits[1 + i] << i for i in range(8))  # LSB first
    edges = [i for i in range(1, len(lv)) if lv[i] != lv[i - 1]]
    return byte, bits[9] == 1, edges


async def rx_send(env, div, byte, stop=1, idle_bits=2):
    """Drive one frame on RXD."""
    bits = [0] + [(byte >> i) & 1 for i in range(8)] + [stop]
    for b in bits:
        env.set_rxd(b)
        await env.cycles(16 * div)
    env.set_rxd(1)
    await env.cycles(idle_bits * 16 * div)


async def wait_rx(env, tries=400):
    for _ in range(tries):
        if (await env.read(STATUS)) & 1:
            return
    raise AssertionError("timeout waiting for RX_AVAIL")


def check_bit_timing(edges, div):
    """edges[0] ends the start bit (up to 1 tick short), the rest must be exact."""
    bit = 16 * div
    assert 15 * div - 1 <= edges[0] <= bit + 1, f"start bit length {edges[0]} clks"
    for a, b in zip(edges, edges[1:]):
        assert b - a == bit, f"bit time {b - a} clks, expected {bit}"


@cocotb.test()
async def test_1_reset_state(dut):
    env = await setup(dut, div=None)
    assert env.pin(4) == 1, "TXD must idle high"
    assert env.pin(0) == 0 and env.pin(1) == 1  # RX empty, TX not full
    assert env.pin(2) == 0 and env.pin(3) == 0  # no flags
    assert int(dut.uio_oe.value) == 0, "bus must not be driven when idle"
    assert int(dut.uo_out.value) >> 7 == 0
    assert await env.read(STATUS) == 0x12  # TX_READY | TX_EMPTY
    assert await env.read(DIV_LO) == 27 and await env.read(DIV_HI) == 0
    assert await env.read(DATA) == 0  # empty RX FIFO reads as 0


@cocotb.test()
async def test_2_send_one_byte(dut):
    env = await setup(dut)
    mon = cocotb.start_soon(tx_frame(env, SIM_DIV))
    await env.write(DATA, 0x55)
    byte, stop_ok, edges = await mon
    dut._log.info(f"decoded 0x{byte:02X}, edges {edges}")
    assert byte == 0x55 and stop_ok
    assert len(edges) == 9  # 0x55 toggles on every bit
    check_bit_timing(edges, SIM_DIV)
    mon = cocotb.start_soon(tx_frame(env, SIM_DIV))
    await env.write(DATA, 0xA5)
    byte, stop_ok, _ = await mon
    assert byte == 0xA5 and stop_ok


@cocotb.test()
async def test_3_receive_one_byte(dut):
    env = await setup(dut)
    await rx_send(env, SIM_DIV, 0x2D)
    assert env.pin(0) == 1, "RX_AVAIL pin"
    assert (await env.read(STATUS)) & 1
    assert await env.read(DATA) == 0x2D
    assert not (await env.read(STATUS)) & 1, "FIFO empty after pop"
    assert env.pin(0) == 0


@cocotb.test(**LONG)
async def test_4_loopback_all_256(dut):
    env = await setup(dut)
    cocotb.start_soon(loopback(env))
    for b in range(256):
        await env.write(DATA, b)
        await wait_rx(env)
        got = await env.read(DATA)
        assert got == b, f"sent 0x{b:02X} got 0x{got:02X}"
    st = await env.read(STATUS)
    assert st & 0xE0 == 0, f"no error flags expected, status=0x{st:02X}"


@cocotb.test(**LONG)
async def test_5_tx_fifo(dut):
    env = await setup(dut)
    # (a) 8 bytes written fast: all sent in order
    seq = [0x11 * i for i in range(1, 9)]
    got = []

    async def collect(n):
        for _ in range(n):
            got.append((await tx_frame(env, SIM_DIV))[0])

    mon = cocotb.start_soon(collect(8))
    for b in seq:
        await env.write(DATA, b)
    await mon
    assert got == seq, f"{got} != {seq}"
    assert not (await env.read(STATUS)) & 0x20, "TX_REJ must be clear"

    # (b) overfill. One byte moves into the shifter at once, so 8 FIFO + 1 shifter = 9
    #     bytes are accepted; the 10th write while full is rejected and flagged.
    seq = [0xA0 + i for i in range(10)]
    got.clear()
    mon = cocotb.start_soon(collect(9))
    for b in seq:
        await env.write(DATA, b)
    assert env.pin(1) == 0, "TX_READY pin low while FIFO full"
    assert (await env.read(STATUS)) & 0x20, "TX_REJ set"
    await mon
    assert got == seq[:9], f"{got}"
    for _ in range(3 * 16 * SIM_DIV):  # no 10th frame
        assert env.pin(4) == 1
        await RisingEdge(dut.clk)
    await env.write(STATUS, 0x20)  # write-1-to-clear
    assert not (await env.read(STATUS)) & 0x20


@cocotb.test()
async def test_6_rx_overrun(dut):
    env = await setup(dut)
    seq = [0x10 + i for i in range(9)]
    for b in seq:
        await rx_send(env, SIM_DIV, b, idle_bits=1)
    assert env.pin(2) == 1, "OVERRUN pin"
    assert env.pin(6) == 1, "RX_FULL pin"
    st = await env.read(STATUS)
    assert st & 0x80 and st & 0x08
    for b in seq[:8]:  # first 8 kept, 9th dropped
        assert await env.read(DATA) == b
    assert not (await env.read(STATUS)) & 1, "9th byte must have been dropped"
    await env.write(STATUS, 0x80)
    assert not (await env.read(STATUS)) & 0x80 and env.pin(2) == 0


@cocotb.test()
async def test_7_framing_error(dut):
    env = await setup(dut)
    await rx_send(env, SIM_DIV, 0x7A, stop=0, idle_bits=2)
    assert env.pin(3) == 1, "FRAME_ERR pin"
    assert (await env.read(STATUS)) & 0x40
    assert await env.read(DATA) == 0x7A  # byte is kept
    assert not (await env.read(STATUS)) & 1, "no spurious second byte"
    await env.write(STATUS, 0x40)
    assert not (await env.read(STATUS)) & 0x40 and env.pin(3) == 0
    await rx_send(env, SIM_DIV, 0x81)  # good frame afterwards works, no new flag
    assert await env.read(DATA) == 0x81
    assert not (await env.read(STATUS)) & 0x40


@cocotb.test()
async def test_8_baud_change(dut):
    env = await setup(dut, div=SIM_DIV)
    await env.set_div(6)
    assert await env.read(DIV_LO) == 6 and await env.read(DIV_HI) == 0
    mon = cocotb.start_soon(tx_frame(env, 6))
    await env.write(DATA, 0x55)
    byte, stop_ok, edges = await mon
    assert byte == 0x55 and stop_ok
    check_bit_timing(edges, 6)  # 96 clks per bit
    await rx_send(env, 6, 0xC5)
    assert await env.read(DATA) == 0xC5
    await env.write(DIV_HI, 1)  # upper byte register works too
    assert await env.read(DIV_HI) == 1
    await env.write(DIV_HI, 0)


@cocotb.test(**LONG)
async def test_9_random_stress(dut):
    env = await setup(dut)
    cocotb.start_soon(loopback(env))
    rng = random.Random(1234)
    sent = [rng.randrange(256) for _ in range(200)]
    expected = list(sent)
    received = []

    async def writer():
        for b in sent:
            while env.pin(1) == 0:  # wait for TX_READY
                await RisingEdge(dut.clk)
            await env.write(DATA, b)
            await env.cycles(rng.choice([0, 0, rng.randrange(1, 3000)]))

    async def reader():
        while len(received) < len(sent):
            if env.pin(0):
                got = await env.read(DATA)
                exp = expected[len(received)]
                assert got == exp, f"byte {len(received)}: got 0x{got:02X} expected 0x{exp:02X}"
                received.append(got)
            else:
                await RisingEdge(dut.clk)

    w = cocotb.start_soon(writer())
    r = cocotb.start_soon(reader())
    await w
    await r
    assert received == sent
    assert (await env.read(STATUS)) & 0xE0 == 0


@cocotb.test(**LONG)
async def test_10_default_divider(dut):
    """Real reset divider (27 = 115740 baud at 50 MHz); no DIV write at all."""
    env = await setup(dut, div=None)
    assert await env.read(DIV_LO) == 27
    cocotb.start_soon(loopback(env))
    mon = cocotb.start_soon(tx_frame(env, 27))
    await env.write(DATA, 0x55)
    byte, stop_ok, edges = await mon
    assert byte == 0x55 and stop_ok
    check_bit_timing(edges, 27)  # 432 clks per bit
    await wait_rx(env, tries=2000)
    assert await env.read(DATA) == 0x55
