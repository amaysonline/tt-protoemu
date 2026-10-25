"""Bus models written as plain classes: call update(cycle, pins) once per system clock with the
resolved pad values; read .drive (dict pin -> 0, 1 or None) afterwards.

The same classes work with the Python model (see harness.py) and inside cocotb tests,
so the RTL and the model are checked against identical devices.
"""


def bit(v, i):
    return (v >> i) & 1


def resolve(dut_out, dut_oe, drives):
    """Wired-AND with pull-ups on every pin: anyone driving 0 wins, otherwise 1."""
    v = 0
    for i in range(8):
        level = 1
        if bit(dut_oe, i) and not bit(dut_out, i):
            level = 0
        for d in drives:
            if d.get(i) == 0:
                level = 0
        v |= level << i
    return v


class UartReceiver:
    """Watches a TX line, samples each bit in the middle, collects bytes."""

    def __init__(self, pin, cycles_per_bit):
        self.pin, self.cpb = pin, cycles_per_bit
        self.bytes, self.errors = [], 0
        self.drive = {}
        self._prev, self._t0, self._busy = 1, None, False

    def update(self, cyc, pins):
        level = bit(pins, self.pin)
        if not self._busy and self._prev == 1 and level == 0:
            self._busy, self._t0 = True, cyc
        elif self._busy:
            k = cyc - self._t0
            if k % self.cpb == self.cpb // 2:
                idx = k // self.cpb  # 0 = start, 1..8 = data, 9 = stop
                if idx == 0:
                    self._val = 0
                    if level != 0:
                        self._busy = False  # glitch
                elif idx <= 8:
                    self._val |= level << (idx - 1)
                else:
                    if level == 1:
                        self.bytes.append(self._val)
                    else:
                        self.errors += 1
                    self._busy = False
        self._prev = level


class UartSender:
    """Drives an RX line with 8N1 frames. Set bad_stop=True to send a framing error."""

    def __init__(self, pin, cycles_per_bit, data, start_at=0, gap_bits=1, bad_stop=False):
        self.pin, self.cpb = pin, cycles_per_bit
        self.bits = []
        for b in data:
            self.bits += [0] + [bit(b, i) for i in range(8)] + [0 if bad_stop else 1] + [1] * gap_bits
        self.start_at = start_at
        self.drive = {pin: 1}

    def update(self, cyc, pins):
        k = (cyc - self.start_at) // self.cpb
        self.drive = {self.pin: self.bits[k] if 0 <= k < len(self.bits) else 1}


class SpiTarget:
    """SPI mode 0 target. Replies with bytes from `replies` (0xFF when it runs out)."""

    def __init__(self, sck, mosi, miso, cs, replies=()):
        self.sck, self.mosi, self.miso, self.cs = sck, mosi, miso, cs
        self.replies = list(replies)
        self.received, self.frames = [], []
        self.drive = {}
        self._psck, self._pcs = 0, 1
        self._rx = self._n = 0
        self._tx = 0xFF

    def update(self, cyc, pins):
        sck, cs = bit(pins, self.sck), bit(pins, self.cs)
        if self._pcs == 1 and cs == 0:  # selected: load the first reply
            self._tx = self.replies.pop(0) if self.replies else 0xFF
            self._rx = self._n = 0
            self._peeked = False
            self.frames.append([])
        if cs == 0:
            if self._psck == 0 and sck == 1:  # rising: sample MOSI
                if self._n == 0 and self._peeked:  # next byte really started: consume it
                    if self.replies:
                        self.replies.pop(0)
                    self._peeked = False
                self._rx = ((self._rx << 1) | bit(pins, self.mosi)) & 0xFF
                self._n += 1
                if self._n == 8:
                    self.received.append(self._rx)
                    self.frames[-1].append(self._rx)
                    self._n = 0
                    # peek the next reply; only consume it if another byte follows
                    self._tx = self.replies[0] if self.replies else 0xFF
                    self._peeked = True
            elif self._psck == 1 and sck == 0 and self._n != 0:  # falling: shift to next bit
                self._tx = (self._tx << 1) & 0xFF
            self.drive = {self.miso: bit(self._tx, 7)}
        else:
            self.drive = {}
        self._psck, self._pcs = sck, cs


class I2cTarget:
    """I2C target with a 7-bit address. ACKs its address and every written byte.
    stretch = number of cycles to hold SCL low after each falling edge (0 = never).

    STARTER SKELETON (Phase 3). START and STOP detection are done. Fill in the TODOs.
    tests expect self.events like:
      [("start",), ("addr", 0x3C, 0, True), ("data", 0x00), ("data", 0xAF), ("stop",)]
    """

    def __init__(self, sda, scl, address, stretch=0):
        self.sda, self.scl, self.addr, self.stretch = sda, scl, address, stretch
        self.events = []
        self.drive = {}
        self._psda, self._pscl = 1, 1
        self._state = "idle"          # idle -> addr -> data (or ignore if not our address)
        self._sr = self._n = 0        # shift register and bit count for the current byte
        self._ack_now = False         # True while we hold SDA low for an ACK
        self._hold = 0                # cycles left of clock stretching
        self._stretched = 0
        self._acking_addr = False

    def update(self, cyc, pins):
        sda, scl = bit(pins, self.sda), bit(pins, self.scl)
        if self._pscl and scl and self._psda and not sda:            # SDA falls, SCL high
            self.events.append(("start",))
            self._state, self._sr, self._n, self._ack_now = "addr", 0, 0, False
        elif self._pscl and scl and not self._psda and sda:          # SDA rises, SCL high
            self.events.append(("stop",))
            self._state, self._ack_now = "idle", False
        elif not self._pscl and scl and self._state in ("addr", "data"):
            # TODO(P3) rising SCL: bits 1-8 shift SDA into self._sr (MSB first). The 9th rising
            #          edge is the ACK clock: reset the bit count, and after the address byte move to
            #          "data" if it was ours, else "ignore".
            pass
        elif self._pscl and not scl:
            # TODO(P3) falling SCL: start clock stretching if self.stretch. After the 8th bit,
            #          log ("addr", address, rw, matched) or ("data", byte) and start ACKing
            #          (only ACK an address if it matches). After the 9th bit, stop ACKing.
            pass
        drive = {}
        if self._ack_now:
            drive[self.sda] = 0
        if self._hold:
            drive[self.scl] = 0
            self._hold -= 1
            self._stretched += 1
        self.drive = drive
        self._psda, self._pscl = sda, scl
