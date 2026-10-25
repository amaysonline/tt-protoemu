"""Phase 1: the v0 core runs programs/uart_tx_v0.s from ROM.
Two checks: the UART line decodes to 'A', and the pin matches the Python model every clock."""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly

from host import PinBus                      # also puts ../tools on the import path
from asm import assemble
from model import Engine
from busmodels import UartReceiver

PROG = os.path.join(os.path.dirname(__file__), "..", "programs", os.environ.get("PROG", "uart_tx_v0.s"))
CLKDIV = 3                                   # must match project_phase1.v


@cocotb.test()
async def test_v0_against_model(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0xFF
    dut.rst_n.value = 0
    words, config, _ = assemble(open(PROG).read())
    config.update(clkdiv=CLKDIV, pins={0: 1}, set_base=0, set_count=1, side_pin=0)
    model = Engine(words, config)
    model.en = 1
    model.p1 = model.p2 = 0xFF
    await ClockCycles(dut.clk, 5)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1                       # released half a clock before the next edge

    rx = UartReceiver(pin=0, cycles_per_bit=8 * (CLKDIV + 1))
    cycle = 0
    for _ in range(8 * (CLKDIV + 1) * 12 * 4):
        expected = model.step(0xFF)[0] & 1    # model's pin 0 after this clock
        await FallingEdge(dut.clk)
        await ReadOnly()
        got = int(dut.uio_out.value) & 1
        assert got == expected, f"cycle {cycle}: RTL pin0={got}, model={expected}, model pc={model.pc}"
        rx.update(cycle, got)
        cycle += 1
    if "uart" in os.path.basename(PROG):
        assert rx.bytes[:3] == [0x41] * 3, rx.bytes
