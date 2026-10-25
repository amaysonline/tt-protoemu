"""MicroPython host driver for the protocol engine (Raspberry Pi Pico or similar).

Wiring (Pico GPIO -> engine): GP2 SCK, GP3 MOSI, GP4 MISO, GP5 CS_N, plus a common ground.
Programs come from the assembler:  python3 tools/asm.py programs/uart_tx.s --py uart_tx.py
then copy uart_tx.py to the Pico next to this file.
"""
import time
from machine import Pin, SPI

CTRL, STATUS, CLKDIV, PINMODE, PINBASE, SETCFG = 0x00, 0x01, 0x02, 0x04, 0x06, 0x07
SIDEJMP, SHIFTCFG, TXFIFO, RXFIFO, IRQCLR, WATCH, IMEM = 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x10, 0x40
TX_FULL, RX_EMPTY, IRQ = 1 << 1, 1 << 2, 1 << 4


class Protoemu:
    def __init__(self, sck=2, mosi=3, miso=4, csn=5, baud=1_000_000):
        # SCK must stay at or below the engine clock / 8 (6.25 MHz at 50 MHz)
        self.spi = SPI(0, baudrate=baud, polarity=0, phase=0,
                       sck=Pin(sck), mosi=Pin(mosi), miso=Pin(miso))
        self.cs = Pin(csn, Pin.OUT, value=1)

    def _xfer(self, data):
        out = bytearray(data)
        inp = bytearray(len(out))
        self.cs(0)
        self.spi.write_readinto(out, inp)
        self.cs(1)
        return inp[1:]

    def write(self, addr, *data):
        self._xfer([0x80 | addr, *data])

    def read(self, addr, n=1):
        r = self._xfer([addr] + [0] * n)
        return r[0] if n == 1 else bytes(r)

    def load(self, words, config):
        c = config
        self.write(CTRL, 0b100)                                   # stop, clear FIFOs
        div = c.get("clkdiv", 0)
        self.write(CLKDIV, div & 0xFF, div >> 8)
        pm = 0
        for p, m in c.get("pins", {}).items():
            pm |= m << (2 * p)
        self.write(PINMODE, pm & 0xFF, pm >> 8)
        self.write(PINBASE, c.get("out_base", 0) | c.get("in_base", 0) << 3)
        self.write(SETCFG, c.get("set_base", 0) | c.get("set_count", 1) << 3)
        self.write(SIDEJMP, c.get("side_pin", 0) | c.get("jmp_pin", 0) << 3)
        self.write(SHIFTCFG, c.get("out_shift", 0) | c.get("in_shift", 0) << 1)
        self.write(WATCH, c.get("watch_mask", 0xFF))
        prog = []
        for w in words:
            prog += [w >> 8, w & 0xFF]
        self.write(IMEM, *prog)
        self.write(CTRL, 0b010)                                   # restart at pc = 0

    def start(self):
        self.write(CTRL, 0b001)

    def stop(self):
        self.write(CTRL, 0b000)

    def status(self):
        return self.read(STATUS)

    def send(self, data, timeout_ms=1000):
        t0 = time.ticks_ms()
        for b in data:
            while self.status() & TX_FULL:
                if time.ticks_diff(time.ticks_ms(), t0) > timeout_ms:
                    raise OSError("TX FIFO stuck full")
            self.write(TXFIFO, b)

    def recv(self, n, timeout_ms=1000):
        out = bytearray()
        t0 = time.ticks_ms()
        while len(out) < n:
            if not self.status() & RX_EMPTY:
                out.append(self.read(RXFIFO))
            elif time.ticks_diff(time.ticks_ms(), t0) > timeout_ms:
                break
        return bytes(out)

    def irq(self):
        return bool(self.status() & IRQ)

    def clear_irq(self):
        self.write(IRQCLR, 0)


def demo_uart(pe):
    import uart_tx                     # made with: asm.py programs/uart_tx.s --py uart_tx.py
    pe.load(uart_tx.WORDS, uart_tx.CONFIG)
    pe.start()
    pe.send(b"Hello from our own chip!\r\n")


def i2c_scan(pe):
    """Every 7-bit address that ACKs. Uses programs/i2c_write.s with N = 0 (address only)."""
    import i2c_write
    pe.load(i2c_write.WORDS, i2c_write.CONFIG)
    pe.start()
    found = []
    for a in range(0x08, 0x78):
        pe.clear_irq()
        pe.send([0, a << 1])
        time.sleep_ms(2)              # one address byte at 100 kHz takes about 0.1 ms
        if not pe.irq():
            found.append(a)
    return found
