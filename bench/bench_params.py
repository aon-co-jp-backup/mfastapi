# -*- coding: utf-8 -*-
"""パラメータ値まで取り出す速さ: Starlette(match + groupdict + convert) vs 拡張 RouteTable.match。
使い方: PYTHONPATH=<mfastapi_native.soのdir> python bench/bench_params.py"""
import platform
import time

import mfastapi_native as ext
from starlette.routing import compile_path


def best(fn, loops, repeats=7):
    t = min((lambda s: (fn(loops), time.perf_counter() - s)[1])(time.perf_counter()) for _ in range(repeats))
    return t / loops * 1e9


def starlette_match(compiled, path):
    """StarletteのRoute.matches相当: 正規表現 → groupdict → convertorでconvert。"""
    for i, (rx, _, conv) in enumerate(compiled):
        m = rx.match(path)
        if m:
            return i, {k: conv[k].convert(v) for k, v in m.groupdict().items()}
    return None


CASES = [
    ("static /health (1 route hit)", ["/health"], "/health"),
    ("/items/{id:int}", ["/items/{id:int}"], "/items/12345"),
    ("/users/{uid}/posts/{pid:int}", ["/users/{uid}/posts/{pid:int}"], "/users/alice/posts/77"),
    ("/files/{p:path}", ["/files/{p:path}"], "/files/a/b/c.txt"),
    ("/u/{u:uuid}", ["/u/{u:uuid}"], "/u/123e4567-e89b-12d3-a456-426614174000"),
    ("/m/{x:float}", ["/m/{x:float}"], "/m/3.14"),
]
print("python", platform.python_version(), platform.system())
print("%-34s %12s %12s %8s" % ("case", "starlette ns", "ext.match ns", "speedup"))
for name, templates, path in CASES:
    compiled = [compile_path(t) for t in templates]
    tbl = ext.RouteTable(templates)
    assert tbl.match(path) == starlette_match(compiled, path), name
    def f_s(n):
        for _ in range(n):
            starlette_match(compiled, path)
    def f_e(n, m=tbl.match):
        for _ in range(n):
            m(path)
    a, b = best(f_s, 20000), best(f_e, 20000)
    print("%-34s %12.0f %12.0f %7.1fx" % (name, a, b, a / b))
