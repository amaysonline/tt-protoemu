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
