"""cocotb helpers: the host SPI driver and a pin bus that connects bus models to the DUT."""
import os
import sys

from cocotb.triggers import ClockCycles, FallingEdge

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from busmodels import resolve  # noqa: E402

SCK, CSN, MOSI = 0, 1, 2          # ui_in bits
REG = dict(CTRL=0x00, STATUS=0x01, CLKDIV=0x02, PINMODE=0x04, PINBASE=0x06, SETCFG=0x07,
           SIDEJMP=0x08, SHIFTCFG=0x09, TXFIFO=0x0A, RXFIFO=0x0B, IRQCLR=0x0C,
           PC=0x0D, X=0x0E, Y=0x0F, WATCH=0x10, IMEM=0x40)


class Host:
    """Drives the host SPI port (mode 0, MSB first). half = clocks per SCK half period."""

    def __init__(self, dut, half=4):
        self.dut, self.half = dut, half
        self.ui = 1 << CSN
        dut.ui_in.value = self.ui

    def _set(self, bitno, v):
        self.ui = (self.ui & ~(1 << bitno)) | (v << bitno)
        self.dut.ui_in.value = self.ui

    async def xfer(self, data):
        got = []
        self._set(CSN, 0)
        await ClockCycles(self.dut.clk, self.half)
        for byte in data:
            rx = 0
            for i in range(7, -1, -1):
                self._set(MOSI, (byte >> i) & 1)
                await ClockCycles(self.dut.clk, self.half)
                miso = str(self.dut.uo_out.value)[-1]      # bit 0; may be X while writing
                rx = (rx << 1) | (miso == "1")              # unwritten memory reads as X
                self._set(SCK, 1)
                await ClockCycles(self.dut.clk, self.half)
                self._set(SCK, 0)
            got.append(rx)
        await ClockCycles(self.dut.clk, self.half)
        self._set(CSN, 1)
        await ClockCycles(self.dut.clk, self.half * 2)
        return got[1:]

    async def write(self, addr, *data):
        await self.xfer([0x80 | addr, *data])

    async def read(self, addr, n=1):
        r = await self.xfer([addr] + [0] * n)
        return r if n > 1 else r[0]

    async def load(self, words, config):
        """Stop the engine, write configuration and program, restart it (engine left stopped)."""
        await self.write(REG["CTRL"], 0b100)                  # stop + clear FIFOs
        c = config
        await self.write(REG["CLKDIV"], c.get("clkdiv", 0) & 0xFF, c.get("clkdiv", 0) >> 8)
        pm = 0
        for p, m in c.get("pins", {}).items():
            pm |= m << (2 * p)
        await self.write(REG["PINMODE"], pm & 0xFF, pm >> 8)
        await self.write(REG["PINBASE"], c.get("out_base", 0) | c.get("in_base", 0) << 3)
        await self.write(REG["SETCFG"], c.get("set_base", 0) | c.get("set_count", 1) << 3)
        await self.write(REG["SIDEJMP"], c.get("side_pin", 0) | c.get("jmp_pin", 0) << 3)
        await self.write(REG["SHIFTCFG"], c.get("out_shift", 0) | c.get("in_shift", 0) << 1)
        await self.write(REG["WATCH"], c.get("watch_mask", 0xFF))
        prog = []
        for w in words:
            prog += [w >> 8, w & 0xFF]
        await self.write(REG["IMEM"], *prog)                 # burst, address auto-increments
        await self.write(REG["CTRL"], 0b010)                  # restart: pc = 0

    async def start(self):
        await self.write(REG["CTRL"], 0b001)


class PinBus:
    """Every clock: resolve the 8 engine pins (wired-AND with pull-ups) and feed uio_in."""

    def __init__(self, dut, devices=()):
        self.dut, self.devices, self.cycle = dut, list(devices), 0
        self.trace = []

    def pins(self):
        out, oe = int(self.dut.uio_out.value), int(self.dut.uio_oe.value)
        return resolve(out, oe, [d.drive for d in self.devices])

    async def run(self):
        while True:
            await FallingEdge(self.dut.clk)
            p = self.pins()
            for d in self.devices:
                d.update(self.cycle, p)
            p = self.pins()
            self.dut.uio_in.value = p
            self.trace.append(p)
            self.cycle += 1
