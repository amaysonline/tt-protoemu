"""pytest: every example program must work on the Python model.
Phase 1: python3 -m pytest -q -k v0      Phase 2 onwards: python3 -m pytest -q"""
import random
from harness import load, run
from busmodels import UartReceiver, UartSender, SpiTarget, I2cTarget


def test_uart_tx_v0():
    e, c, _ = load("uart_tx_v0.s", clkdiv=3)
    rx = UartReceiver(0, 8 * 4)
    run(e, 8 * 4 * 12 * 5, [rx])
    assert rx.bytes[:4] == [0x41] * 4 and rx.errors == 0


def test_square_v0():
    e, c, _ = load("square_v0.s", clkdiv=0)
    trace = []
    run(e, 40, [], trace)
    pin0 = [p & 1 for p in trace]
    edges = [t for t in range(1, len(pin0)) if pin0[t] != pin0[t - 1]]
    assert len(edges) >= 6 and all(b - a == 4 for a, b in zip(edges, edges[1:])), pin0


def test_uart_tx():
    data = [0x41, 0x00, 0xFF, 0x5A, 0x96]
    e, c, _ = load("uart_tx.s", clkdiv=3)
    e.tx.extend(data[:4])
    rx = UartReceiver(0, 8 * 4)
    run(e, 32 * 11 * 3, [rx])
    e.tx.append(data[4])                      # refill while running
    run(e, 32 * 11 * 4, [rx])
    assert rx.bytes == data, rx.bytes


def test_uart_tx_real_baud():
    e, c, _ = load("uart_tx.s")               # clkdiv 53 -> 432 clocks/bit
    e.tx.extend([0xA5, 0x3C])
    rx = UartReceiver(0, 434)                 # ideal 115200 at 50 MHz
    run(e, 434 * 25, [rx])
    assert rx.bytes == [0xA5, 0x3C]


def test_uart_rx():
    data = [0x55, 0x00, 0xFF, 0x81]
    e, c, _ = load("uart_rx.s", clkdiv=3)
    tx = UartSender(1, 32, data, start_at=50)
    got = []
    for _ in range(40):
        run(e, 32 * 2, [tx])
        while e.rx:
            got.append(e.rx.popleft())
    assert got == data, got
    assert e.irq == 0


def test_uart_rx_baud_error():
    # sender 3% fast must still decode
    data = [random.randrange(256) for _ in range(6)]
    e, c, _ = load("uart_rx.s", clkdiv=3)
    tx = UartSender(1, 31, data, start_at=7)
    got = []
    for _ in range(60):
        run(e, 64, [tx])
        while e.rx:
            got.append(e.rx.popleft())
    assert got == data


def test_uart_rx_framing_error():
    e, c, _ = load("uart_rx.s", clkdiv=3)
    tx = UartSender(1, 32, [0x12], start_at=10, bad_stop=True, gap_bits=3)
    run(e, 32 * 16, [tx])
    assert e.irq == 1 and len(e.rx) == 0


def test_spi_master():
    e, c, _ = load("spi_master.s", clkdiv=3)
    tgt = SpiTarget(sck=2, mosi=3, miso=4, cs=5, replies=[0xC3, 0x5A, 0x01])
    e.tx.extend([0x9F, 0x00, 0xFE])
    trace = []
    run(e, 3000, [tgt], trace)
    assert tgt.received == [0x9F, 0x00, 0xFE]
    assert [f for f in tgt.frames] == [[0x9F], [0x00], [0xFE]]
    assert list(e.rx) == [0xC3, 0x5A, 0x01]
    # SCK must idle low whenever CS is high
    assert all(((p >> 2) & 1) == 0 for p in trace[50:] if (p >> 5) & 1)


def i2c_run(stretch=0, addr=0x3C, target_addr=0x3C, data=(0x00, 0xAF)):
    e, c, _ = load("i2c_write.s", clkdiv=3)
    tgt = I2cTarget(sda=6, scl=7, address=target_addr, stretch=stretch)
    e.tx.extend([len(data), addr << 1])
    pending = list(data)
    for _ in range(400):
        run(e, 50, [tgt])
        while pending and len(e.tx) < 4:
            e.tx.append(pending.pop(0))
    return e, tgt


def test_i2c_write():
    e, tgt = i2c_run()
    assert tgt.events == [("start",), ("addr", 0x3C, 0, True), ("data", 0x00), ("data", 0xAF), ("stop",)], tgt.events
    assert e.irq == 0


def test_i2c_clock_stretching():
    e, tgt = i2c_run(stretch=40)
    assert tgt._stretched > 0
    assert tgt.events == [("start",), ("addr", 0x3C, 0, True), ("data", 0x00), ("data", 0xAF), ("stop",)]


def test_i2c_nack():
    e, tgt = i2c_run(addr=0x50, target_addr=0x3C, data=(0x11,))
    assert e.irq == 1
    assert tgt.events[0] == ("start",) and tgt.events[1][3] is False and tgt.events[-1] == ("stop",)


def test_sniffer():
    e, c, _ = load("sniffer.s", clkdiv=0)
    # toggle pin 7 at known times, pin 6 once
    edges = {100: 0x80, 130: 0x00, 200: 0xC0, 207: 0x40}
    level = 0

    class Driver:
        drive = {}

        def update(self, cyc, pins):
            nonlocal level
            if cyc in edges:
                level = edges[cyc]
            self.drive = {i: (level >> i) & 1 for i in range(8)}
    out = []
    d = Driver()
    for _ in range(10):
        run(e, 30, [d])
        while e.rx:
            out.append(e.rx.popleft())
    # stream: state, delta, state, delta, ...
    states, deltas = out[0::2], out[1::2]
    assert states[:4] == [0x80, 0x00, 0xC0, 0x40], out
    assert deltas[:3] == [30, 70, 7], out
