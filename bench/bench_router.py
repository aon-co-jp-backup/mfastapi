# -*- coding: utf-8 -*-
"""Starlette Router のルート探索(ASGI呼び出し全体)の速さ: 本家 vs fastapim.accelerate。
エンドポイントは何もしないASGIアプリにして、探索とディスパッチの費用だけを測る。
使い方: PYTHONPATH=<fastapim_native.soのdir>:<repo>/python python bench/bench_router.py"""
import asyncio
import platform
import time

from starlette.routing import Route, Router

from fastapim import accelerate


class Hit:
    async def __call__(self, scope, receive, send):
        return None


async def receive():
    return {"type": "http.request"}


async def send(message):
    return None


KINDS = ["/api/v1/res{i}/{{id:int}}", "/api/v1/res{i}/{{name}}/detail", "/static{i}/{{p:path}}",
         "/users{i}/{{uid}}/posts/{{pid:int}}", "/svc{i}/items", "/h{i}/{{u:uuid}}"]


def build(n):
    return Router(routes=[Route(KINDS[i % len(KINDS)].format(i=i), Hit()) for i in range(n)])


def scope(path):
    return {"type": "http", "method": "GET", "path": path, "root_path": "", "headers": [], "query_string": b""}


async def run(router, sc, loops):
    for _ in range(loops):
        await router(dict(sc), receive, send)


def best(router, sc, loops, repeats=5):
    t = 1e9
    for _ in range(repeats):
        s = time.perf_counter()
        asyncio.run(run(router, sc, loops))
        t = min(t, time.perf_counter() - s)
    return t / loops * 1e9


print("python", platform.python_version(), platform.system())
print("%-6s %-8s %12s %12s %8s" % ("routes", "target", "starlette ns", "accel ns", "speedup"))
for n in (10, 50, 200, 1000):
    base, fast = build(n), build(n)
    accelerate(fast)
    last = KINDS[(n - 1) % len(KINDS)].format(i=n - 1).replace("{id:int}", "7").replace("{name}", "abc").replace(
        "{p:path}", "a/b").replace("{uid}", "u1").replace("{pid:int}", "9").replace(
        "{u:uuid}", "123e4567-e89b-12d3-a456-426614174000")
    for tgt, path in (("first", "/api/v1/res0/42"), ("last", last), ("miss-404", "/nope/zzz")):
        loops = max(50, 4000 // n)
        a, b = best(base, scope(path), loops), best(fast, scope(path), loops)
        print("%-6d %-8s %12.0f %12.0f %7.1fx" % (n, tgt, a, b, a / b))
