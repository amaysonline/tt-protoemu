"""Run the Python model against bus models."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from asm import assemble          # noqa: E402
from model import Engine          # noqa: E402
from busmodels import resolve     # noqa: E402

PROG_DIR = os.path.join(os.path.dirname(__file__), "..", "programs")


def load(name, **overrides):
    words, config, labels = assemble(open(os.path.join(PROG_DIR, name)).read())
    config.update(overrides)
    e = Engine(words, config)
    e.en = 1
    return e, config, labels


def run(engine, cycles, devices=(), trace=None):
    out, oe = engine.pads()
    start = getattr(engine, "cycle", 0)
    for cyc in range(start, start + cycles):
        pins = resolve(out, oe, [d.drive for d in devices])
        if trace is not None:
            trace.append(pins)
        for d in devices:
            d.update(cyc, pins)
        pins = resolve(out, oe, [d.drive for d in devices])
        out, oe = engine.step(pins)
    engine.cycle = start + cycles
    return engine
