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
                pass  # TODO(P2): open-drain drives 0 (oe = 1, out = 0) only when v == 0
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
        # TODO(P2): WAIT (opcode 1): stall until pin arg & 7 equals arg >> 7, or, for WAIT CHANGE
        #           (arg & 0x40), until ((pins ^ self.snap) & self.watch_mask) != 0.
        #           PUSH/PULL (opcode 4) without noblock: stall while the FIFO can't be used.
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
                else:
                    raise NotImplementedError("TODO(P2): conditions !x, x--, !y, y--, x!=y, pin, !osre")
                if take:
                    nxt = addr
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
                # TODO(P1): SET PINS (dst 0): set_count pins (at most 5) from set_base get the low
                #           bits of the value: set pmask and pdata like OUT does.
                # TODO(P2): SET X (dst 1) and SET Y (dst 2).
                raise NotImplementedError("TODO(P1) SET")
            else:
                # TODO(P2): WAIT (snapshot on WAIT CHANGE), IN, PUSH/PULL, MOV (TIME is read-and-
                #           restart: set time_next = 1), IRQ. Look at the RTL you wrote: same rules.
                raise NotImplementedError(f"TODO(P2) opcode {opc}")
            self.pc = nxt
            self.dly = delay
        ov = (self.out_val & ~pmask) | (pdata & pmask)
        # TODO(P1): side-set: if sse, force bit side_pin of ov to ssv (even when stalled).
        self.out_val = ov & M8
        self.time = time_next
