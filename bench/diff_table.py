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
    compiled = [compile_path(t) for t in templates]
    rxs = [c[0] for c in compiled]
    try:
        table = ext.RouteTable(templates)
    except Exception as e:  # 重複パラメータ名はStarlette側もValueErrorで拒否している(compile_pathで除外済みのはず)
        print("RouteTable rejected", ascii(templates), e)
        bad += 1
        continue
    assert table.size() == len(templates)
    for _ in range(4):
        p = path()
        want = next((i for i, rx in enumerate(rxs) if rx.match(p)), -1)
        got = table.first_match(p)
        if got != want:
            bad += 1
            print("MISMATCH table", ascii(templates), ascii(p), want, got)
        # path_params: Starletteのgroupdict + convertor.convert と一致するか
        got_m = table.match(p)
        if want == -1:
            ok = got_m is None
        else:
            m = rxs[want].match(p)
            exp = {k: compiled[want][2][k].convert(v) for k, v in m.groupdict().items()}
            ok = got_m is not None and got_m[0] == want and got_m[1] == exp and all(
                type(got_m[1][k]) is type(exp[k]) for k in exp)
        if not ok:
            bad += 1
            print("MISMATCH params", ascii(templates), ascii(p), want, got_m)
        i = rng.randrange(len(templates))
        if ext.path_matches(templates[i], p) != (rxs[i].match(p) is not None):
            bad += 1
            print("MISMATCH single", ascii(templates[i]), ascii(p))
        single += 1
print("cases=%d, mismatches=%d" % (N * 4 * 2, bad))
sys.exit(1 if bad else 0)
