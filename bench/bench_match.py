# -*- coding: utf-8 -*-
"""ルート照合の速度: Starlette(コンパイル済み正規表現を順に試す) vs ネイティブ(1件ずつ呼ぶ/表を一括)。
使い方: FASTAPIM_LIB=<lib> python bench/bench_match.py   (Python 3 + starlette)"""
import os, sys, time, platform
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "python", "fastapim"))
import native
try:
    import fastapim_native as ext
except ImportError:
    ext = None
from starlette.routing import compile_path

def make_routes(n):
    kinds = ["/api/v1/res{i}/{{id:int}}", "/api/v1/res{i}/{{name}}/detail", "/static{i}/{{p:path}}",
             "/users{i}/{{uid}}/posts/{{pid:int}}", "/svc{i}/items", "/h{i}/{{u:uuid}}"]
    return [kinds[i % len(kinds)].format(i=i) for i in range(n)]

def best(fn, loops, repeats=7):
    t = min((lambda: (lambda s: (fn(loops), time.perf_counter() - s)[1])(time.perf_counter()))() for _ in range(repeats))
    return t / loops * 1e9  # ns/call

def main():
    print("python", platform.python_version(), platform.system(), "lib", os.environ.get("FASTAPIM_LIB"))
    print("%-5s %-7s %10s %12s %12s %12s %12s %8s %8s" % ("N", "target", "starlette", "ctypes 1x1", "ctypes batch", "ext linear", "ext trie", "ctypes", "ext"))
    for n in (10, 50, 200, 1000, 3000):
        routes = make_routes(n)
        rxs = [compile_path(r)[0] for r in routes]
        packed = native.pack_templates(routes)
        tbl = ext.RouteTable(routes) if ext else None
        paths = {"first": "/api/v1/res0/42", "last": None, "miss": "/nope/zzz"}
        last = routes[-1].replace("{id:int}", "7").replace("{name}", "abc").replace("{p:path}", "a/b").replace("{uid}", "u1").replace("{pid:int}", "9").replace("{u:uuid}", "123e4567-e89b-12d3-a456-426614174000")
        paths["last"] = last
        for tgt, path in paths.items():
            def f_star(loops):
                m = rxs; p = path
                for _ in range(loops):
                    for i, rx in enumerate(m):
                        if rx.match(p): break
            def f_one(loops):
                pm = native.path_matches; p = path; rs = routes
                for _ in range(loops):
                    for r in rs:
                        if pm(r, p): break
            def f_batch(loops):
                rf = native.route_first_match; p = path
                for _ in range(loops):
                    rf(packed, p)
            def f_lin(loops):
                fm = tbl.first_match_linear; p = path
                for _ in range(loops):
                    fm(p)
            def f_ext(loops):
                fm = tbl.first_match; p = path
                for _ in range(loops):
                    fm(p)
            # 結果の一致確認
            want = next((i for i, rx in enumerate(rxs) if rx.match(path)), -1)
            assert native.route_first_match(packed, path) == want, (tgt, want)
            assert tbl is None or tbl.first_match(path) == want, (tgt, want)
            loops = max(100, 20000 // n)
            a, b, c = best(f_star, loops), best(f_one, loops), best(f_batch, loops)
            d = best(f_ext, loops) if tbl else float("nan")
            l = best(f_lin, loops) if tbl else float("nan")
            print("%-5d %-7s %10.0f %12.0f %12.0f %12.0f %12.0f %7.1fx %7.1fx" % (n, tgt, a, b, c, l, d, a / c, a / d))

main()
