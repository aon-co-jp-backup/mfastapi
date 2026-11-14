# -*- coding: utf-8 -*-
"""Differential fuzz of the Rust core against Pydantic (int) and urllib.parse.parse_qsl (query). Needs pydantic; FASTAPIM_RS_LIB set."""
import random
import sys
import urllib.parse as up

from pydantic import TypeAdapter

from fastapim import core

ta = TypeAdapter(int)
rnd = random.Random(20261114)
ALPHA = "0123456789 +-_.eE" + chr(9) + chr(233) + chr(1635) + "abx%"
cases = ["0", "-0", "+0", "00", "1_0", "1_", "_1", "1__0", "5.0", "5.", ".5", "5.0.0", " 5", "5 ", "1e1", "+-1", "--1", "1 2", "", " ", "-", "+",
         "9223372036854775807", "9223372036854775808", "-9223372036854775808", "-9223372036854775809", "1_000.0", "007", "5.00", chr(1635)]
cases += [a + b for a in ("0", "00", "0_", "+0", "+00", "-0", "0__", "") for b in ("-5", "-05", "-0", "-5.0", "-5_0", "--5", "-", "-_5", "-5_", "-+5", "- 5", "-5 ", "-__5", "-_05", "-_0", "-5__0")]
cases += ["".join(rnd.choice(ALPHA) for _ in range(rnd.randint(0, 8))) for _ in range(5000)]
bad = 0
for s in cases:
    try:
        want = ta.validate_python(s)
    except Exception:
        want = None
    try:
        got = core.parse_int(s)
    except OverflowError:
        got = "overflow"
    if got == "overflow":
        if want is None or -(1 << 63) <= want < (1 << 63):
            bad += 1
            print("INT DIFF", repr(s), want, got)
    elif got != want:
        bad += 1
        print("INT DIFF", repr(s), want, got)
print("int: %d cases, differences=%d" % (len(cases), bad))

QA = "abn%+=&;.é "
bad2 = 0
qs = ["".join(rnd.choice(QA) for _ in range(rnd.randint(0, 14))) for _ in range(5000)]
qs += ["n=5&n=7", "n", "&&n=3&", "a=1;n=2", "n=%2B1", "n=a+b", "n=%zz", "n=%e3%81%82", "n=%ff", "%6e=x"]
for q in qs:
    for name in ("n", "a", "b"):
        pairs = up.parse_qsl(q, keep_blank_values=True, separator="&")
        vals = [v for k, v in pairs if k == name]
        want = vals[-1] if vals else None
        got = core.query_last(q, name)
        if got != want:
            bad2 += 1
            if bad2 < 15:
                print("QUERY DIFF", repr(q), name, repr(want), repr(got))
print("query: %d cases, differences=%d" % (len(qs) * 3, bad2))
sys.exit(1 if bad or bad2 else 0)
