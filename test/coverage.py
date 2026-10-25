"""Functional coverage: count what the engine actually did during a test.

RTL only (it looks inside the core), so skip it when GATES=yes. Usage in a test:
    cov = Coverage(dut); cocotb.start_soon(cov.run())
    ... run the test ...
    cov.report(dut._log)
Phase 4: add bins until your whole suite hits every one of them.
"""
import collections

from cocotb.triggers import FallingEdge


class Coverage:
    NAMES = ["jmp", "wait", "in", "out", "push/pull", "mov", "set", "irq"]

    def __init__(self, dut):
        self.core = dut.user_project.u_core
        self.clk = dut.clk
        self.bins = collections.Counter()

    async def run(self):
        c = self.core
        while True:
            await FallingEdge(self.clk)
            if not int(c.exec.value):          # no tick, or counting down a delay
                continue
            op = self.NAMES[int(c.opc.value)]
            if int(c.stall.value):
                self.bins[f"{op} stalled"] += 1
                continue
            self.bins[op] += 1
            if op == "jmp":
                cond = int(c.arg.value) >> 5
                self.bins[f"jmp cond {cond} {'taken' if int(c.take.value) else 'not taken'}"] += 1
            if int(c.sse.value):
                self.bins["side-set"] += 1
            # TODO(P4): bins for each IN/OUT/MOV source and destination, both shift directions,
            #           FIFO full and empty, each pin mode, delays 0..7, noblock with an empty FIFO

    def report(self, log):
        for k in sorted(self.bins):
            log.info(f"{k:28s} {self.bins[k]}")
