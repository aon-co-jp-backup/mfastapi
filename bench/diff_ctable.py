# -*- coding: utf-8 -*-
"""C版コンパイル済みルート表(native.CTable)を Starlette の照合と突き合わせる(Python 3 + starlette)。
使い方: MFASTAPI_LIB=<libmfastapi_c.so|mfastapi.dll> PYTHONPATH=<repo>/python python bench/diff_ctable.py [件数]"""
import random
import sys

from mfastapi import native
from starlette.routing import compile_path

N = int(sys.argv[1]) if len(sys.argv) > 1 else 20000
rng = random.Random(4242)
SEG = ["a", "b", "ab", "items", "v1", "-", ".", "é", "あ"]
PARAMS = ["{x}", "{id:int}", "{n:float}", "{p:path}", "{u:uuid}", "{s:str}", "{}", "{1x}"]
SAMPLES = ["a", "b", "ab", "items", "v1", "42", "0", "3.14", "-", ".", "é", "あ", "",
           "123e4567-e89b-12d3-a456-426614174000", "٣", "a\n"]


def tpl():
    out = ""
    for _ in range(rng.randint(0, 4)):
        seg = ""
        for _ in range(rng.randint(1, 3)):
            seg += rng.choice(SEG) if rng.random() < 0.6 else rng.choice(PARAMS)
        out += "/" + seg
    return out or "/"


def path():
    return "/" + "/".join(rng.choice(SAMPLES) for _ in range(rng.randint(0, 4)))


assert native.table_available(), "library has no compiled table"
bad = 0
cases = 0
for _ in range(N):
    templates = []
    target = rng.choice([1, 3, 12, 12, 60, 150])
    while len(templates) < target:
        t = tpl()
        try:
            compile_path(t)
        except (AssertionError, ValueError):
            continue
        templates.append(t)
    rxs = [compile_path(t)[0] for t in templates]
    table = native.CTable(templates)
    assert table.size() == len(templates)
    for _ in range(4):
        p = path()
        want = next((i for i, rx in enumerate(rxs) if rx.match(p)), -1)
        got = table.first_match(p)
        cases += 1
        if got != want:
            bad += 1
            print("MISMATCH table", ascii(templates), ascii(p), want, got)
        st = rng.randrange(len(templates) + 1)
        want_from = next((i for i in range(st, len(rxs)) if rxs[i].match(p)), -1)
        got_from = table.first_match_from(p, st)
        cases += 1
        if got_from != want_from:
            bad += 1
            print("MISMATCH from", ascii(templates), ascii(p), st, want_from, got_from)
print("cases=%d, mismatches=%d" % (cases, bad))
sys.exit(1 if bad else 0)
