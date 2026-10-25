#!/usr/bin/env python3
"""Assembler for the protocol engine ISA (v1 + v1.1 extensions).

STARTER SKELETON: parsing, labels, directives, delays and side-set are done. The encoders
for most instructions are TODOs. 'jmp' and 'nop' are done as worked examples.
Run the checks with:  cd tools && python3 -m pytest -q

Instruction word (16 bits):
  [15:13] opcode  [12] side-set enable  [11] side-set value  [10:8] delay  [7:0] argument
"""
import re
import sys

OPC = {"jmp": 0, "wait": 1, "in": 2, "out": 3, "pushpull": 4, "mov": 5, "set": 6, "irq": 7}
JMP_COND = {"": 0, "!x": 1, "x--": 2, "!y": 3, "y--": 4, "x!=y": 5, "pin": 6, "!osre": 7}
IN_SRC = {"pins": 0, "x": 1, "y": 2, "null": 3}
OUT_DST = {"pins": 0, "x": 1, "y": 2, "null": 3}
MOV_DST = {"pins": 0, "x": 1, "y": 2, "isr": 3, "osr": 4}
MOV_SRC = {"pins": 0, "x": 1, "y": 2, "isr": 3, "osr": 4, "null": 5, "time": 6}
SET_DST = {"pins": 0, "x": 1, "y": 2}

CFG_KEYS = {"clkdiv", "pin", "out_base", "in_base", "set_base", "set_count",
            "side_pin", "jmp_pin", "out_shift", "in_shift", "watch_mask"}
PIN_MODES = {"input": 0, "pushpull": 1, "opendrain": 2}


class AsmError(Exception):
    pass


def num(tok, line):
    try:
        return int(tok, 0)
    except ValueError:
        raise AsmError(f"line {line}: expected a number, got '{tok}'")


def assemble(text):
    """Returns (words, config, labels)."""
    lines = []
    labels = {}
    config = {"pins": {}}
    # pass 1: strip comments, collect labels and directives
    for n, raw in enumerate(text.splitlines(), 1):
        s = re.split(r";|//|#", raw, maxsplit=1)[0].strip()
        if not s:
            continue
        while ":" in s and not s.startswith("."):
            lab, s = s.split(":", 1)
            lab = lab.strip()
            if lab in labels:
                raise AsmError(f"line {n}: label '{lab}' defined twice")
            labels[lab] = len(lines)
            s = s.strip()
        if not s:
            continue
        if s.startswith("."):
            parts = s[1:].replace(",", " ").split()
            key = parts[0]
            if key == "program":
                continue
            if key not in CFG_KEYS:
                raise AsmError(f"line {n}: unknown directive .{key}")
            if key == "pin":
                config["pins"][num(parts[1], n)] = PIN_MODES[parts[2]]
            elif key in ("out_shift", "in_shift"):
                config[key] = 1 if parts[1] == "msb" else 0
            else:
                config[key] = num(parts[1], n)
            continue
        lines.append((n, s))
    if len(lines) > 32:
        raise AsmError(f"program has {len(lines)} instructions; the limit is 32")

    words = []
    for addr, (n, s) in enumerate(lines):
        # suffixes: [delay] and side v
        delay = 0
        m = re.search(r"\[\s*(\w+)\s*\]\s*$", s)
        if m:
            delay = num(m.group(1), n)
            s = s[:m.start()].strip()
        sse = ssv = 0
        m = re.search(r"\bside\s+(\w+)\s*$", s)
        if m:
            sse, ssv = 1, num(m.group(1), n)
            s = s[:m.start()].strip()
        if not 0 <= delay <= 7:
            raise AsmError(f"line {n}: delay must be 0..7")
        if ssv not in (0, 1):
            raise AsmError(f"line {n}: side value must be 0 or 1")

        op, _, rest = s.partition(" ")
        args = [a.strip() for a in rest.split(",")] if rest.strip() else []

        def sym(table, tok, what):
            if tok not in table:
                raise AsmError(f"line {n}: bad {what} '{tok}'")
            return table[tok]

        def target(tok):
            if tok in labels:
                return labels[tok]
            v = num(tok, n)
            if not 0 <= v < 32:
                raise AsmError(f"line {n}: jump target out of range")
            return v

        def count(tok):
            c = num(tok, n)
            if not 1 <= c <= 8:
                raise AsmError(f"line {n}: bit count must be 1..8")
            return c & 7  # 8 encodes as 0

        if op == "jmp":
            cond, dest = ("", args[0]) if len(args) == 1 else (args[0], args[1])
            opc, arg = OPC["jmp"], (sym(JMP_COND, cond, "condition") << 5) | target(dest)
        elif op == "wait":
            # TODO(P2): 'wait 0|1 pin N' -> arg = polarity << 7 | N
            #           'wait change'    -> arg = 1 << 6
            raise AsmError(f"line {n}: TODO(P2) encode wait")
        elif op == "in":
            # TODO(P2): arg = source << 5 | count(bits)   (sources in IN_SRC)
            raise AsmError(f"line {n}: TODO(P2) encode in")
        elif op == "out":
            # TODO(P2): arg = destination << 5 | count(bits)   (destinations in OUT_DST)
            raise AsmError(f"line {n}: TODO(P2) encode out")
        elif op in ("push", "pull"):
            # TODO(P2): arg = (op == pull) << 7 | (noblock) << 6; 'block' is the default
            raise AsmError(f"line {n}: TODO(P2) encode {op}")
        elif op == "mov":
            # TODO(P2): 'mov dst, src', 'mov dst, ~src' (invert), 'mov dst, ::src' (bit-reverse)
            #           arg = dst << 5 | op << 3 | src   (op: 0 none, 1 invert, 2 reverse)
            raise AsmError(f"line {n}: TODO(P2) encode mov")
        elif op == "nop":
            opc, arg = OPC["mov"], (MOV_DST["y"] << 5) | MOV_SRC["y"]
        elif op == "set":
            # TODO(P1): 'set pins|x|y, value' with value 0..31 -> arg = dst << 5 | value
            raise AsmError(f"line {n}: TODO(P1) encode set")
        elif op == "irq":
            # TODO(P2): 'irq set' -> arg = 0x80, 'irq clear' -> arg = 0
            raise AsmError(f"line {n}: TODO(P2) encode irq")
        else:
            raise AsmError(f"line {n}: unknown instruction '{op}'")

        words.append((opc << 13) | (sse << 12) | (ssv << 11) | (delay << 8) | arg)
    return words, config, labels


def main():
    import argparse
    p = argparse.ArgumentParser(description="protocol engine assembler")
    p.add_argument("source")
    p.add_argument("-o", "--out", help="hex output file (one word per line)")
    p.add_argument("--vh", help="also write a Verilog ROM include file")
    p.add_argument("--py", help="also write a Python file for the MicroPython host driver")
    a = p.parse_args()
    try:
        words, config, _ = assemble(open(a.source).read())
    except AsmError as e:
        sys.exit(f"{a.source}: {e}")
    out = a.out or a.source.rsplit(".", 1)[0] + ".hex"
    with open(out, "w") as f:
        f.writelines(f"{w:04x}\n" for w in words)
    if a.vh:
        with open(a.vh, "w") as f:
            for i, w in enumerate(words):
                f.write(f"5'd{i}: rom_data = 16'h{w:04x};\n")
    if a.py:
        with open(a.py, "w") as f:
            f.write(f"# generated from {a.source}\nWORDS = {[hex(w) for w in words]}\n".replace("'", ""))
            f.write(f"CONFIG = {config!r}\n")
    print(f"{len(words)} instructions -> {out}")
    print("config:", config)


if __name__ == "__main__":
    main()
