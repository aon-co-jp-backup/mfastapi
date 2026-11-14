# -*- coding: utf-8 -*-
"""FastAPI アプリ(何もしない軽いルートN本)のASGI呼び出し全体の速さ: 本家 vs fastapim.accelerate。
ルート探索だけでなく、FastAPIの依存解決・応答生成を含む総所要時間なので、探索の改善は相対的に薄まる点に注意。
使い方: PYTHONPATH=<native>:<repo>/python python bench/bench_router_fastapi.py"""
import asyncio
import platform
import time

from fastapi import FastAPI

from fastapim import accelerate


def build(n):
    app = FastAPI()
    for i in range(n):
        if i % 2:
            app.add_api_route("/api/v1/res%d/{rid}" % i, lambda rid: {"ok": 1}, methods=["GET"])
        else:
            app.add_api_route("/svc%d/items" % i, lambda: {"ok": 1}, methods=["GET"])
    return app


def scope(path):
    return {"type": "http", "method": "GET", "path": path, "raw_path": path.encode(), "root_path": "",
            "headers": [], "query_string": b"", "http_version": "1.1", "scheme": "http",
            "server": ("t", 80), "client": ("c", 1)}


async def receive():
    return {"type": "http.request", "body": b"", "more_body": False}


async def send(message):
    return None


async def run(app, path, loops):
    for _ in range(loops):
        await app(scope(path), receive, send)


def best(app, path, loops, repeats=5):
    t = 1e9
    for _ in range(repeats):
        s = time.perf_counter()
        asyncio.run(run(app, path, loops))
        t = min(t, time.perf_counter() - s)
    return t / loops * 1e9


print("python", platform.python_version(), platform.system())
print("%-6s %-8s %12s %12s %8s" % ("routes", "target", "fastapi ns", "accel ns", "speedup"))
for n in (10, 50, 200, 1000):
    base, fast = build(n), build(n)
    accelerate(fast)
    last = ("/api/v1/res%d/7" % (n - 1)) if (n - 1) % 2 else ("/svc%d/items" % (n - 1))
    first = "/svc0/items"
    for tgt, path in (("first", first), ("last", last), ("miss-404", "/nope/zzz")):
        loops = max(30, 3000 // n)
        a, b = best(base, path, loops), best(fast, path, loops)
        print("%-6d %-8s %12.0f %12.0f %7.1fx" % (n, tgt, a, b, a / b))
