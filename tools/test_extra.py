"""pytest: small checks that the example programs don't cover yet.
Run with the rest:  cd tools && python3 -m pytest -q"""
import pytest
from asm import assemble, AsmError
from model import Engine


def one(line):
    return assemble(line)[0][0]


def test_asm_encodings():
    # [15:13] opcode  [12] side-set enable  [11] side-set value  [10:8] delay  [7:0] argument
    assert one("set pins, 1 [7]") == 0xC701
    assert one("wait 1 pin 7 [2]") == 0x2287
    assert one("wait change") == 0x2040
    assert one("in pins, 8") == 0x4000          # a count of 8 is stored as 0
    assert one("in null, 3") == 0x4063
    assert one("out null, 8 side 1") == 0x7860
    assert one("push") == 0x8000
    assert one("push noblock") == 0x8040
    assert one("pull") == 0x8080
    assert one("pull noblock [7]") == 0x87C0
    assert one("mov pins, ::isr") == 0xA013     # '::' must not be read as a label
    assert one("mov x, ~y") == 0xA02A
    assert one("mov osr, time") == 0xA086
    assert one("nop") == 0xA042                 # mov y, y
    assert one("set y, 31") == 0xC05F
    assert one("irq set") == 0xE080
    assert one("irq clear") == 0xE000
    assert one("jmp !osre, 0") == 0x00E0
    assert one("jmp x!=y, 3") == 0x00A3


def test_asm_labels():
    words, _, labels = assemble("a: b: nop\nloop:\n  jmp loop\n")
    assert labels == {"a": 0, "b": 0, "loop": 1} and words[1] == 0x0001


@pytest.mark.parametrize("bad", ["set pins, 32", "in pins, 9", "wait 2 pin 0", "wait 1 pin 8",
                                 "mov pins, time2", "push maybe", "irq toggle", "nop [8]"])
def test_asm_rejects(bad):
    with pytest.raises(AsmError):
        assemble(bad)


def test_pin_modes():
    # pin 0 input, pin 1 push-pull, pin 2 open-drain
    e = Engine(config={"pins": {0: 0, 1: 1, 2: 2}})
    e.out_val = 0b111
    assert e.pads() == (0b010, 0b010)           # open-drain 1 = let go of the line
    e.out_val = 0b000
    assert e.pads() == (0b000, 0b110)           # open-drain 0 = drive low; push-pull drives 0


def test_side_set_holds_while_stalled():
    words, config, _ = assemble(".pin 0 pushpull\n.side_pin 0\nset pins, 0\npull side 1\n")
    e = Engine(words, config)
    e.en = 1
    for _ in range(20):
        out, oe = e.step(0xFF)
    assert e.stalled() and e.pc == 1 and out & 1 == 1
