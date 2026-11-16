# Lab notebook

Dated entries: what we tried, what broke, which bug a test caught.

## 25 October 2026: Phase 0 hardening numbers

From the first green gds run on GitHub (run 40218721626, commit 223955e, hard-wired UART transmitter, 6x4 tiles):

| Measure | Value |
|---|---|
| Logic cells (everything except fill) | 217 |
| of which flip-flops (sequential cells) | 24 |
| of which combinational cells | 117 |
| of which inverters | 11 |
| of which buffers (1 plain, 5 clock, 59 timing repair) | 65 |
| Fill cells | 70,895 |
| Placement utilisation | 0.272 % |
| Routed wire length | 3,442 um |
| Setup slack at 50 MHz | TODO: copy from the gds run summary page (Actions > gds > Summary) |

Takeaway: the Phase 0 design uses well under 1 % of the area, so there is a lot of room.

## 10 November 2026: Phase 1 Python tools (assembler and model)

Filled in by Claude at Amay's request; `src/pe_core.v` stays ours to write.

- `tools/asm.py`: `set` is encoded as `dst << 5 | value`, value 0 to 31. Check: `set pins, 1 [7]` gives `0xC701`.
- `tools/model.py`: SET PINS builds a mask and data like OUT PINS (`set_count` capped at 5, rotated by `set_base`); side-set forces bit `side_pin` last, so it wins and also applies while stalled.
- `python3 -m pytest -q -k v0`: 2 passed.
- Seen failing: with the side-set line changed to only OR the bit in (so it can never drive 0), `test_square_v0` fails because pin 0 stays at 1.

Still open for Phase 1: the five TODO(P1) spots in `src/pe_core.v`, `PHASE ?= 1` in `test/Makefile`, and the three deliberate-bug checks on the RTL.

## 16 November 2026: Phase 2 Python tools (assembler and model)

Written by Claude at Amay's request, with Aarav's agreement. The Verilog stays ours to write.

- `tools/asm.py`: `wait`, `in`, `out`, `push`, `pull`, `mov`, `irq` now encode.
- `tools/model.py`: every instruction, all eight jump conditions, stalls, both FIFOs, the timer, the snapshot, and open-drain pins.
- `docs/isa.md`: new section "Encodings the assembler never produces". The random test will hit these, so the model needed a rule for each. We chose the simplest ones; review them before writing the RTL.
- `python3 -m pytest -q -k "not i2c"`: 21 passed (9 program tests plus 12 new small ones in `tools/test_extra.py`). The 3 I2C tests still fail, as expected, until the I2C target model is written in Phase 3.
- 300 random 32-word programs, 3,000 clocks each, run on the model without an exception or an out-of-range value.

Bug found in the starter kit: the label parser split lines at any `:`, so `mov pins, ::isr` was read as a label and failed with "unknown instruction 'isr'". Found by assembling one line of every instruction form. Fixed (a label is now a name followed by a single `:`), with a test.

Bugs planted in the model on purpose, and what caught them:

| Planted bug | Caught by |
|---|---|
| `x--` never decrements | 6 tests (UART and SPI loops never end) |
| `pull` never stalls | 2 tests |
| `in` with LSB first puts new bits at the bottom | 2 tests |
| `jmp pin` uses the `in_base`-rotated pins | 1 test |
| Reading the timer restarts it at 0, not 1 | 1 test (`test_sniffer`) |
| `wait change` takes no snapshot | 1 test (`test_sniffer`) |
| Open-drain drives on 1 instead of 0 | Nothing at first (only I2C uses open-drain). Added `test_pin_modes`, which catches it |
