# -*- coding: utf-8 -*-
"""段階A+: 同じ計算を 純Python / Mojo で行うFastAPIエンドポイントの速さ(ASGI経由、TestClientを使わず直接呼ぶ)。
使い方: PYTHONPATH=<fastapim_handlers.soのdir>:<repo>/python python bench/bench_handlers.py"""
import asyncio
import os
import platform
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tests", "mojo_endpoint"))
import test_endpoint as t  # noqa: E402


async def receive():
    return {"type": "http.request", "body": b"", "more_body": False}


async def send(m):
    return None


def scope(path, qs=b""):
    return {"type": "http", "method": "GET", "path": path, "raw_path": path.encode(), "root_path": "", "headers": [],
            "query_string": qs, "http_version": "1.1", "scheme": "http", "server": ("t", 80), "client": ("c", 1)}


async def run(app, path, qs, loops):
    for _ in range(loops):
        await app(scope(path, qs), receive, send)


def best(app, path, qs, loops, repeats=3):
    b = 1e9
    for _ in range(repeats):
        s = time.perf_counter()
        asyncio.run(run(app, path, qs, loops))
        b = min(b, time.perf_counter() - s)
    return b / loops * 1e6


print("python", platform.python_version(), platform.system())
print("%-28s %12s %12s %9s" % ("endpoint", "python us", "mojo us", "speedup"))
py, mj = t.build(False), t.build(True)
for label, path, qs, loops in (
    ("fib(10)", "/fib/10", b"", 300), ("fib(25)", "/fib/25", b"", 5), ("fib(30)", "/fib/30", b"", 2),
    ("primes(n=1000)", "/primes", b"n=1000", 200), ("primes(n=1,000,000)", "/primes", b"n=1000000", 3),
    ("primes(n=10,000,000)", "/primes", b"n=10000000", 1),
    ("words(short)", "/words", b"text=hello%20world", 500),
):
    a, b = best(py, path, qs, loops), best(mj, path, qs, loops)
    print("%-28s %12.1f %12.1f %8.1fx" % (label, a, b, a / b))
