import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly

from host import Host, PinBus, REG
from asm import assemble
from model import Engine
from busmodels import UartReceiver, UartSender, SpiTarget, I2cTarget

PROG = os.path.join(os.path.dirname(__file__), "..", "programs")
GATES = os.environ.get("GATES") == "yes"


async def setup(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())   # 50 MHz
    dut.ena.value = 1
    dut.ui_in.value = 0b010
    dut.uio_in.value = 0xFF
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)
    return Host(dut)


def prog(name, **over):
    words, config, labels = assemble(open(os.path.join(PROG, name)).read())
    config.update(over)
    return words, config


@cocotb.test()
async def test_registers(dut):
    host = await setup(dut)
    await host.write(REG["CLKDIV"], 0x34, 0x12)
    assert await host.read(REG["CLKDIV"], 2) == [0x34, 0x12]
    await host.write(REG["PINBASE"], 0b101_011)
    assert await host.read(REG["PINBASE"]) == 0b101_011
    await host.write(REG["IMEM"] + 6, 0xAB, 0xCD, 0xEF, 0x01)   # instructions 3 and 4
    assert await host.read(REG["IMEM"] + 6, 4) == [0xAB, 0xCD, 0xEF, 0x01]
    st = await host.read(REG["STATUS"])
    assert st & 0b0101 == 0b0101                                  # both FIFOs empty


@cocotb.test()
async def test_uart_tx_v0(dut):
    host = await setup(dut)
    rx = UartReceiver(pin=0, cycles_per_bit=32)
    bus = PinBus(dut, [rx])
    cocotb.start_soon(bus.run())
    await host.load(*prog("uart_tx_v0.s", clkdiv=3))
    await host.start()
    await ClockCycles(dut.clk, 32 * 12 * 4)
    assert rx.bytes[:3] == [0x41] * 3 and rx.errors == 0


@cocotb.test()
async def test_uart_tx(dut):
    host = await setup(dut)
    rx = UartReceiver(pin=0, cycles_per_bit=32)
    cocotb.start_soon(PinBus(dut, [rx]).run())
    await host.load(*prog("uart_tx.s", clkdiv=3))
    await host.start()
    data = [0x41, 0x00, 0xFF, 0x5A, 0x96, 0x3C]
    for b in data:
        while int(dut.uo_out.value) & 0b1000 == 0:      # uo_out[3]: TX FIFO has space
            await ClockCycles(dut.clk, 8)
        await host.write(REG["TXFIFO"], b)
    await ClockCycles(dut.clk, 32 * 11 * 5)
    assert rx.bytes == data, rx.bytes


@cocotb.test()
async def test_uart_rx(dut):
    host = await setup(dut)
    data = [0x55, 0x00, 0xFF, 0x81, 0x7E]
    tx = UartSender(pin=1, cycles_per_bit=32, data=data, start_at=10**9, gap_bits=2)
    bus = PinBus(dut, [tx])
    cocotb.start_soon(bus.run())
    await host.load(*prog("uart_rx.s", clkdiv=3))
    await host.start()
    tx.start_at = bus.cycle + 100                         # start sending once the engine runs
    got = []
    for _ in range(300):
        if int(dut.uo_out.value) & 0b100:                 # uo_out[2]: RX FIFO has data
            got.append(await host.read(REG["RXFIFO"]))
        else:
            await ClockCycles(dut.clk, 32)
        if len(got) == len(data):
            break
    assert got == data, got
    assert int(dut.uo_out.value) & 0b10 == 0              # no IRQ


@cocotb.test()
async def test_spi_master(dut):
    host = await setup(dut)
    tgt = SpiTarget(sck=2, mosi=3, miso=4, cs=5, replies=[0xC3, 0x5A, 0x01])
    cocotb.start_soon(PinBus(dut, [tgt]).run())
    await host.load(*prog("spi_master.s", clkdiv=3))
    await host.start()
    for b in (0x9F, 0x00, 0xFE):
        await host.write(REG["TXFIFO"], b)
    await ClockCycles(dut.clk, 3 * 16 * 8 + 200)
    assert tgt.frames == [[0x9F], [0x00], [0xFE]], tgt.frames
    assert await host.read(REG["RXFIFO"], 3) == [0xC3, 0x5A, 0x01]


async def i2c_case(dut, stretch=0, addr=0x3C, data=(0x00, 0xAF)):
    host = await setup(dut)
    tgt = I2cTarget(sda=6, scl=7, address=0x3C, stretch=stretch)
    cocotb.start_soon(PinBus(dut, [tgt]).run())
    await host.load(*prog("i2c_write.s", clkdiv=3))
    await host.start()
    await host.write(REG["TXFIFO"], len(data))
    await host.write(REG["TXFIFO"], addr << 1)
    for b in data:
        await host.write(REG["TXFIFO"], b)
    await ClockCycles(dut.clk, 4 * 9 * 32 * (len(data) + 2) + 40 * stretch * 30)
    return host, tgt


@cocotb.test()
async def test_i2c_write(dut):
    host, tgt = await i2c_case(dut)
    assert tgt.events == [("start",), ("addr", 0x3C, 0, True), ("data", 0x00), ("data", 0xAF), ("stop",)], tgt.events


@cocotb.test()
async def test_i2c_clock_stretching(dut):
    host, tgt = await i2c_case(dut, stretch=25)
    assert tgt._stretched > 0
    assert tgt.events == [("start",), ("addr", 0x3C, 0, True), ("data", 0x00), ("data", 0xAF), ("stop",)], tgt.events


@cocotb.test()
async def test_i2c_nack(dut):
    host, tgt = await i2c_case(dut, addr=0x50, data=(0x11,))
    assert int(dut.uo_out.value) & 0b10                   # IRQ raised
    assert tgt.events[-1] == ("stop",)
    await host.write(REG["IRQCLR"], 0)
    await ClockCycles(dut.clk, 4)
    assert int(dut.uo_out.value) & 0b10 == 0


@cocotb.test()
async def test_sniffer(dut):
    host = await setup(dut)
    edges = {100: 0x80, 130: 0x00, 200: 0xC0, 207: 0x40}   # cycle (after start) -> pins

    class Driver:
        drive = {}
        level = 0
        base = 10**9

        def update(self, cyc, pins):
            Driver.level = edges.get(cyc - Driver.base, Driver.level)
            self.drive = {i: (Driver.level >> i) & 1 for i in range(8)}
    bus = PinBus(dut, [Driver()])
    cocotb.start_soon(bus.run())
    await host.load(*prog("sniffer.s", clkdiv=0))
    await host.start()
    Driver.base = bus.cycle
    await ClockCycles(dut.clk, 400)                # let all edges happen
    out = await host.read(REG["RXFIFO"], 4)        # FIFO holds 4 bytes
    assert out[0::2] == [0x80, 0x00] and out[1] == 30, out


@cocotb.test(skip=GATES)
async def test_random_vs_model(dut):
    """Random programs on RTL and on the Python model, compared pin-by-pin every clock.
    White-box (peeks at internal signals to line the two up), so RTL only."""
    host = await setup(dut)
    rng = random.Random(int(os.environ.get("SEED", "1")))
    ext = {"v": 0xFF}

    class Noise:
        drive = {}

        def update(self, cyc, pins):
            if rng.random() < 0.02:
                ext["v"] = rng.randrange(256)
            self.drive = {i: (ext["v"] >> i) & 1 for i in range(8)}
    bus = PinBus(dut, [Noise()])
    cocotb.start_soon(bus.run())
    for trial in range(int(os.environ.get("TRIALS", "12"))):
        words = [rng.randrange(1 << 16) for _ in range(32)]
        # keep jumps useful: half of them unconditional loops back
        config = dict(clkdiv=rng.choice([0, 0, 1, 3]),
                      pins={p: rng.choice([0, 1, 2]) for p in range(8)},
                      out_base=rng.randrange(8), in_base=rng.randrange(8),
                      set_base=rng.randrange(8), set_count=rng.randrange(8),
                      side_pin=rng.randrange(8), jmp_pin=rng.randrange(8),
                      out_shift=rng.randrange(2), in_shift=rng.randrange(2),
                      watch_mask=rng.randrange(256))
        await host.load(words, config)
        tx_bytes = [rng.randrange(256) for _ in range(rng.randrange(5))]
        for b in tx_bytes:
            await host.write(REG["TXFIFO"], b)
        top = dut.user_project
        cocotb.start_soon(host.start())
        while True:                       # find the exact clock where the engine is enabled
            await FallingEdge(dut.clk)
            await ReadOnly()
            if int(top.ctrl_en.value):
                break
        # align: model state = RTL state at this falling edge (engine has not ticked yet)
        m = Engine(words, config)
        m.en = 1
        m.out_val = int(top.u_core.out_val.value)
        m.p1, m.p2 = int(top.pin_s1.value), int(top.pin_s2.value)
        m.tx.extend(tx_bytes)
        for cyc in range(3000):
            exp = m.step(int(dut.uio_in.value))
            await FallingEdge(dut.clk)
            await ReadOnly()
            got = (int(dut.uio_out.value), int(dut.uio_oe.value))
            assert got == exp, f"trial {trial} cycle {cyc}: RTL {got} model {exp} pc={m.pc}"
        assert int(top.u_core.pc.value) == m.pc and int(top.u_core.x.value) == m.x
        assert int(top.u_core.y.value) == m.y
        await ClockCycles(dut.clk, 40)    # let host.start() finish
        await host.write(REG["CTRL"], 0b100)
