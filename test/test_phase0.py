"""Phase 0: check the hard-wired UART TX by decoding its output line."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

CLKS_PER_BIT = 434          # must match the RTL parameter


def tx_bit(dut):
    return int(dut.uo_out.value) & 1


async def uart_read_byte(dut):
    while tx_bit(dut) == 1:                          # wait for the start bit
        await ClockCycles(dut.clk, 1)
    await ClockCycles(dut.clk, CLKS_PER_BIT // 2)    # move to the middle of the bit
    assert tx_bit(dut) == 0, "start bit glitch"
    value = 0
    for i in range(8):                               # LSB first
        await ClockCycles(dut.clk, CLKS_PER_BIT)
        value |= tx_bit(dut) << i
    await ClockCycles(dut.clk, CLKS_PER_BIT)
    assert tx_bit(dut) == 1, "missing stop bit"
    return value


@cocotb.test()
async def test_uart_tx(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())   # 50 MHz
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    for sent in [0x41, 0x00, 0xFF, 0x5A]:
        dut.ui_in.value = sent
        await uart_read_byte(dut)          # finish the frame already in flight
        got = await uart_read_byte(dut)
        assert got == sent, f"sent {sent:#04x}, got {got:#04x}"
