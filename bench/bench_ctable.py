# -*- coding: utf-8 -*-
"""C版ルート表(native.CTable)の first_match の速さを、Starlette(正規表現を順に)と比べる。
使い方: MFASTAPI_LIB=<lib> PYTHONPATH=<repo>/python python bench/bench_ctable.py"""
import time

from mfastapi import native
from starlette.routing import compile_path

KINDS = ["/api/v1/res{i}/{{id:int}}", "/api/v1/res{i}/{{name}}/detail", "/static{i}/{{p:path}}",
         "/users{i}/{{uid}}/posts/{{pid:int}}", "/svc{i}/items", "/h{i}/{{u:uuid}}"]


def best(fn, loops=2000, repeats=5):
    t = 1e9
    for _ in range(repeats):
        s = time.perf_counter()
        for _ in range(loops):
            fn()
        t = min(t, time.perf_counter() - s)
    return t / loops * 1e9


print("%-6s %-6s %12s %12s %8s" % ("routes", "target", "starlette ns", "ctable ns", "speedup"))
for n in (10, 50, 200, 1000, 3000):
    tpls = [KINDS[i % 6].format(i=i) for i in range(n)]
    rxs = [compile_path(t)[0] for t in tpls]
    tb = native.CTable(tpls)
    last = tpls[-1].replace("{id:int}", "7").replace("{name}", "abc").replace("{p:path}", "a/b").replace(
        "{uid}", "u1").replace("{pid:int}", "9").replace("{u:uuid}", "123e4567-e89b-12d3-a456-426614174000")
    for tgt, p in (("first", "/api/v1/res0/42"), ("last", last), ("miss", "/nope/zzz")):
        a = best(lambda: next((i for i, rx in enumerate(rxs) if rx.match(p)), -1), loops=max(20, 4000 // n))
        b = best(lambda: tb.first_match(p), loops=max(20, 4000 // n))
        assert tb.first_match(p) == next((i for i, rx in enumerate(rxs) if rx.match(p)), -1)
        print("%-6d %-6s %12.0f %12.0f %7.1fx" % (n, tgt, a, b, a / b))
