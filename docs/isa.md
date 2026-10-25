# Protocol engine ISA, v1.1

This is the contract between the hardware (`src/pe_core.v`), the model (`tools/model.py`)
and the assembler (`tools/asm.py`). Change this file first, then the code.

## Machine state

| Name | Width | Meaning |
|---|---|---|
| `pc` | 5 | program counter, 32 instructions, wraps from 31 to 0 |
| `dly` | 3 | delay ticks left after the current instruction |
| `X`, `Y` | 8 | scratch registers, loop counters |
| `OSR`, `ocnt` | 8, 4 | output shift register; bits shifted out so far (8 = empty) |
| `ISR`, `icnt` | 8, 4 | input shift register; bits shifted in so far |
| `out_val` | 8 | what the engine wants each pin to be; resets to `0xFF` |
| `timer` | 8 | counts ticks, sticks at 255, restarts when read by `MOV` |
| `snap` | 8 | pin snapshot taken by `WAIT CHANGE` |
| `irq` | 1 | flag the host can see and clear |

## Timing

* One **tick** every `clkdiv + 1` clocks. Nothing in the engine moves between ticks.
* An instruction takes **1 tick**, then waits **delay** more ticks (0-7).
* `WAIT`, and `PULL`/`PUSH` without `noblock`, can **stall**: they retry every tick and their delay
  starts only once they complete.
* **Side-set** applies on the first tick of the instruction, even while it stalls, and wins over
  `OUT`/`SET`/`MOV` writes to the same pin.
* Pin inputs pass through 2 flip-flops, so the engine sees them 2 clocks late.

## Instruction word

```
 15 14 13 | 12 | 11 | 10  9  8 | 7  6  5  4  3  2  1  0
  opcode  | SS | SV |  delay   |        argument
```

SS = side-set enable, SV = side-set value (applied to `side_pin`).

| Opcode | Assembly | Argument bits | Meaning |
|---|---|---|---|
| 0 | `jmp [cond,] target` | `[7:5]` cond, `[4:0]` target | jump if cond |
| 1 | `wait 0\|1 pin N` | `[7]` level, `[6]` 0, `[2:0]` N | stall until pin N = level |
| 1 | `wait change` | `[6]` 1 | stall until a watched pin differs from `snap`, then `snap` = pins |
| 2 | `in src, n` | `[7:5]` src, `[2:0]` n (0 = 8) | shift n bits from src into ISR |
| 3 | `out dst, n` | `[7:5]` dst, `[2:0]` n (0 = 8) | shift n bits out of OSR into dst |
| 4 | `push [noblock]` | `[7]` 0, `[6]` noblock | ISR to RX FIFO, ISR = 0 |
| 4 | `pull [noblock]` | `[7]` 1, `[6]` noblock | TX FIFO to OSR (noblock + empty: OSR = X) |
| 5 | `mov dst, [~\|::]src` | `[7:5]` dst, `[4:3]` op, `[2:0]` src | copy, op 1 = invert, 2 = bit-reverse |
| 6 | `set dst, value` | `[7:5]` dst, `[4:0]` value | dst = value (0-31) |
| 7 | `irq set\|clear` | `[7]` 1 = set | set or clear the IRQ flag |
| - | `nop` | | assembles as `mov y, y` |

### Fields

* **jmp cond**: 0 always, 1 `!x` (X = 0), 2 `x--` (X != 0, then X - 1), 3 `!y`, 4 `y--`,
  5 `x!=y`, 6 `pin` (`jmp_pin` is high), 7 `!osre` (OSR not empty). `x--`/`y--` always decrement.
* **in src**: 0 `pins` (from `in_base`), 1 `x`, 2 `y`, 3 `null` (zeros).
* **out dst**: 0 `pins` (n pins from `out_base`), 1 `x`, 2 `y`, 3 `null` (discard).
* **mov dst**: 0 `pins` (all 8, rotated by `out_base`), 1 `x`, 2 `y`, 3 `isr` (icnt = 0), 4 `osr` (ocnt = 0).
* **mov src**: 0 `pins`, 1 `x`, 2 `y`, 3 `isr`, 4 `osr`, 5 `null`, 6 `time` (read and restart).
* **set dst**: 0 `pins` (`set_count` pins from `set_base`, at most 5), 1 `x`, 2 `y`.

### Shift directions (`SHIFTCFG`)

* `out_shift lsb` (bit 0 = 0): data leaves from bit 0, OSR shifts right. `msb`: from bit 7, shifts left.
* `in_shift lsb` (bit 1 = 0): data enters at bit 7, ISR shifts right, so after 8 bits the first bit
  received is bit 0. `msb`: data enters at bit 0, ISR shifts left.

## Assembler directives

`.clkdiv N`, `.pin N input|pushpull|opendrain`, `.out_base N`, `.in_base N`, `.set_base N`,
`.set_count N`, `.side_pin N`, `.jmp_pin N`, `.out_shift lsb|msb`, `.in_shift lsb|msb`,
`.watch_mask M`. Suffixes on any instruction: `side 0|1` and `[delay]`, in that order.

## Register map (host SPI)

| Addr | Name | Bits |
|---|---|---|
| 0x00 | CTRL | [0] enable, [1] restart (self-clearing), [2] clear FIFOs (self-clearing) |
| 0x01 | STATUS (read) | [0] TX empty, [1] TX full, [2] RX empty, [3] RX full, [4] IRQ, [5] RX overflow, [6] stalled |
| 0x02, 0x03 | CLKDIV | low, high byte |
| 0x04, 0x05 | PINMODE | 2 bits per pin, pin 0 in bits [1:0]: 00 input, 01 push-pull, 10 open-drain |
| 0x06 | PINBASE | [2:0] out_base, [5:3] in_base |
| 0x07 | SETCFG | [2:0] set_base, [5:3] set_count |
| 0x08 | SIDEJMP | [2:0] side_pin, [5:3] jmp_pin |
| 0x09 | SHIFTCFG | [0] out MSB first, [1] in MSB first |
| 0x0A | TXFIFO (write) | push a byte for the engine |
| 0x0B | RXFIFO (read) | pop a byte from the engine (0 if empty) |
| 0x0C | IRQCLR (write) | any write clears IRQ |
| 0x0D, 0x0E, 0x0F | PC, X, Y (read) | debug |
| 0x10 | WATCH | watch mask for `wait change` |
| 0x40-0x7F | IMEM | instruction i: high byte at 0x40 + 2i, low byte at 0x41 + 2i |

SPI transaction (mode 0, MSB first, SCK at most clk/8): CS low, command byte `{write, addr[6:0]}`,
then data bytes. The address auto-increments after each data byte, except at 0x0A and 0x0B.

## Pins

| Pin | Use |
|---|---|
| `ui_in[0..2]` | host SCK, CS_N, MOSI |
| `uo_out[0..3]` | host MISO, IRQ, RX FIFO has data, TX FIFO has space |
| `uio[0..7]` | engine pins 0-7 |
