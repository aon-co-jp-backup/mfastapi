# -*- coding: utf-8 -*-
"""拡張モジュールの RouteTable.first_match / path_matches を Starlette と突き合わせる(Python 3 + starlette)。
使い方: PYTHONPATH=<mfastapi_native.soのあるdir> python bench/diff_table.py [件数]"""
import random
import sys

import mfastapi_native as ext
from starlette.routing import compile_path

N = int(sys.argv[1]) if len(sys.argv) > 1 else 20000
rng = random.Random(777)
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


bad = 0
single = 0
for _ in range(N):
    templates = []
    while len(templates) < rng.randint(1, 12):
        t = tpl()
        try:
            compile_path(t)
        except (AssertionError, ValueError):
            continue
        templates.append(t)
    rxs = [compile_path(t)[0] for t in templates]
    table = ext.RouteTable(templates)
    assert table.size() == len(templates)
    for _ in range(4):
        p = path()
        want = next((i for i, rx in enumerate(rxs) if rx.match(p)), -1)
        got = table.first_match(p)
        if got != want:
            bad += 1
            print("MISMATCH table", ascii(templates), ascii(p), want, got)
        i = rng.randrange(len(templates))
        if ext.path_matches(templates[i], p) != (rxs[i].match(p) is not None):
            bad += 1
            print("MISMATCH single", ascii(templates[i]), ascii(p))
        single += 1
print("cases=%d, mismatches=%d" % (N * 4 * 2, bad))
sys.exit(1 if bad else 0)
