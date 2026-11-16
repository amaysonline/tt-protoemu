"""Cycle-accurate Python model of the protocol engine (one call to step() = one system clock).

It must match the RTL exactly: 2-flop input synchronisers, clock divider, delay counter,
side-set priority, FIFO depth 4.

STARTER SKELETON: the clocking, synchronisers, delay counter and OUT are done.
Fill in the TODO(P1) parts in Phase 1 and the TODO(P2) parts in Phase 2.
"""
from collections import deque

M8 = 0xFF


def mask(n):
    return (1 << n) - 1


def rotl(v, b):
    b &= 7
    return ((v << b) | (v >> (8 - b))) & M8 if b else v & M8


def rotr(v, b):
    b &= 7
    return ((v >> b) | (v << (8 - b))) & M8 if b else v & M8


def rev8(v):
    return int(f"{v & M8:08b}"[::-1], 2)


class Engine:
    FIFO_DEPTH = 4

    def __init__(self, words=(), config=None):
        self.imem = [0] * 32
        for i, w in enumerate(words):
            self.imem[i] = w
        # config registers
        self.clkdiv = 0
        self.pinmode = [0] * 8
        self.out_base = self.in_base = self.set_base = 0
        self.set_count = 1
        self.side_pin = self.jmp_pin = 0
        self.out_msb = self.in_msb = 0
        self.watch_mask = 0xFF
        self.en = 0
        if config:
            self.apply_config(config)
        # state
        self.divcnt = 0
        self.p1 = self.p2 = 0
        self.tx = deque()
        self.rx = deque()
        self.irq = 0
        self.rx_ovf = 0
        self.out_val = 0xFF  # every line starts high: UART idle, CS inactive, I2C released
        self.restart()

    def apply_config(self, c):
        self.clkdiv = c.get("clkdiv", self.clkdiv)
        for p, m in c.get("pins", {}).items():
            self.pinmode[p] = m
        for k in ("out_base", "in_base", "set_base", "set_count", "side_pin", "jmp_pin", "watch_mask"):
            if k in c:
                setattr(self, k, c[k])
        self.out_msb = c.get("out_shift", self.out_msb)
        self.in_msb = c.get("in_shift", self.in_msb)

    def restart(self):
        self.pc = 0
        self.dly = 0
        self.x = self.y = 0
        self.isr = self.osr = 0
        self.icnt = 0
        self.ocnt = 8
        self.time = 0
        self.snap = 0

    # ---- pad view -------------------------------------------------------
    def pads(self):
        out = oe = 0
        for i in range(8):
            v = (self.out_val >> i) & 1
            if self.pinmode[i] == 1:
                out |= v << i
                oe |= 1 << i
            elif self.pinmode[i] == 2:
                if v == 0:      # open-drain: pull the line low, or let go of it. Never drive 1.
                    oe |= 1 << i
        return out, oe

    # ---- one system clock -------------------------------------------------
    def step(self, uio_in):
        pins = self.p2
        tick = self.en and self.divcnt >= self.clkdiv
        if not self.en or tick:
            self.divcnt = 0
        else:
            self.divcnt += 1
        if tick:
            self._tick(pins)
        self.p2, self.p1 = self.p1, uio_in & M8
        return self.pads()

    def stalled(self):
        w = self.imem[self.pc]
        return self.en and self.dly == 0 and self._stall(w, self.p2)

    def _stall(self, w, pins):
        opc, arg = w >> 13, w & M8
        if opc == 1:  # WAIT
            if arg & 0x40:  # WAIT CHANGE: until a watched pin differs from the snapshot
                return ((pins ^ self.snap) & self.watch_mask) == 0
            return ((pins >> (arg & 7)) & 1) != (arg >> 7)  # WAIT pin: until pin N has the level
        if opc == 4 and not arg & 0x40:  # PUSH/PULL without noblock
            if arg & 0x80:
                return not self.tx  # PULL waits for a byte
            return len(self.rx) >= self.FIFO_DEPTH  # PUSH waits for space
        return False

    def _tick(self, pins):
        time_next = min(self.time + 1, 255)
        if self.dly:
            self.dly -= 1
            self.time = time_next
            return
        w = self.imem[self.pc]
        opc = w >> 13
        sse, ssv = (w >> 12) & 1, (w >> 11) & 1
        delay, arg = (w >> 8) & 7, w & M8
        stall = self._stall(w, pins)
        in_val = rotr(pins, self.in_base)
        pmask = pdata = 0
        nxt = (self.pc + 1) & 31
        if not stall:
            if opc == 0:  # JMP
                cond, addr = arg >> 5, arg & 31
                if cond == 0:
                    take = True
                elif cond == 1:  # !x
                    take = self.x == 0
                elif cond == 2:  # x--: test first, then always decrement
                    take = self.x != 0
                    self.x = (self.x - 1) & M8
                elif cond == 3:  # !y
                    take = self.y == 0
                elif cond == 4:  # y--
                    take = self.y != 0
                    self.y = (self.y - 1) & M8
                elif cond == 5:  # x!=y
                    take = self.x != self.y
                elif cond == 6:  # pin: raw pin jmp_pin, not rotated by in_base
                    take = bool((pins >> self.jmp_pin) & 1)
                else:  # !osre: output shift register not empty
                    take = self.ocnt != 8
                if take:
                    nxt = addr
            elif opc == 1:  # WAIT: the waiting is in _stall(); completing WAIT CHANGE takes a snapshot
                if arg & 0x40:
                    self.snap = pins
            elif opc == 2:  # IN
                n = (arg & 7) or 8
                src = arg >> 5
                d = (in_val, self.x, self.y)[src] & mask(n) if src < 3 else 0  # 3 = null; 4..7 undefined, read as zeros
                if self.in_msb:  # shift left, new bits enter at the bottom
                    self.isr = ((self.isr << n) | d) & M8
                else:            # shift right, new bits enter at the top
                    self.isr = ((self.isr >> n) | (d << (8 - n))) & M8
                self.icnt = min(self.icnt + n, 8)
            elif opc == 3:  # OUT  (done: the worked example)
                n = (arg & 7) or 8
                dst = arg >> 5
                if self.out_msb:
                    d = (self.osr >> (8 - n)) & mask(n)
                    self.osr = (self.osr << n) & M8
                else:
                    d = self.osr & mask(n)
                    self.osr = self.osr >> n
                self.ocnt = min(self.ocnt + n, 8)
                if dst == 0:
                    pmask, pdata = rotl(mask(n), self.out_base), rotl(d, self.out_base)
                elif dst == 1:
                    self.x = d
                elif dst == 2:
                    self.y = d
            elif opc == 6:  # SET
                dst, value = arg >> 5, arg & 31
                if dst == 0:
                    # SET PINS: set_count pins (at most 5) from set_base get the low bits of
                    # the value. Same mask-and-data shape as OUT PINS above.
                    k = min(self.set_count, 5)
                    pmask, pdata = rotl(mask(k), self.set_base), rotl(value & mask(k), self.set_base)
                elif dst == 1:
                    self.x = value
                elif dst == 2:
                    self.y = value
            elif opc == 4:  # PUSH / PULL (a blocking one only gets here once the FIFO can be used)
                if arg & 0x80:  # PULL: TX FIFO -> OSR. Empty (noblock only): OSR = X
                    self.osr = self.tx.popleft() if self.tx else self.x
                    self.ocnt = 0
                else:           # PUSH: ISR -> RX FIFO. Full (noblock only): byte dropped, overflow flag
                    if len(self.rx) < self.FIFO_DEPTH:
                        self.rx.append(self.isr)
                    else:
                        self.rx_ovf = 1
                    self.isr = 0
                    self.icnt = 0
            elif opc == 5:  # MOV
                dst, mop, src = arg >> 5, (arg >> 3) & 3, arg & 7
                if src == 6:    # TIME is read-and-restart
                    v = self.time
                    time_next = 1
                else:           # 5 = null; 7 undefined, reads as zero
                    v = (in_val, self.x, self.y, self.isr, self.osr, 0, 0, 0)[src]
                if mop == 1:
                    v = ~v & M8
                elif mop == 2:
                    v = rev8(v)
                if dst == 0:    # all 8 pins, rotated by out_base
                    pmask, pdata = M8, rotl(v, self.out_base)
                elif dst == 1:
                    self.x = v
                elif dst == 2:
                    self.y = v
                elif dst == 3:
                    self.isr, self.icnt = v, 0
                elif dst == 4:
                    self.osr, self.ocnt = v, 0
            else:  # opc == 7, IRQ
                self.irq = arg >> 7
            self.pc = nxt
            self.dly = delay
        ov = (self.out_val & ~pmask) | (pdata & pmask)
        # Side-set: force bit side_pin of ov to ssv. This sits outside "if not stall", so it
        # applies even while the instruction stalls, and it comes last, so it beats OUT/SET/MOV.
        if sse:
            ov = (ov & ~(1 << self.side_pin)) | (ssv << self.side_pin)
        self.out_val = ov & M8
        self.time = time_next
