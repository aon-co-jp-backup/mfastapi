# -*- coding: utf-8 -*-
"""accelerate()した Starlette / FastAPI アプリが、しない場合と完全に同じ応答を返すことを確かめる。
実行: PYTHONPATH=<mfastapi_native.soのdir>:<repo>/python python tests/accel/test_router_equiv.py
(要 starlette fastapi httpx)"""
import itertools
import random
import sys

from fastapi import APIRouter, FastAPI, Request
from fastapi.testclient import TestClient
from starlette.applications import Starlette
from starlette.responses import JSONResponse, PlainTextResponse
from starlette.routing import Mount, Route

import mfastapi
from mfastapi import accelerate


def make_routes_for_starlette():
    async def echo(request: Request):
        return JSONResponse({"params": {k: repr(v) for k, v in request.path_params.items()}, "method": request.method})

    def r(path, methods=None):
        return Route(path, echo, methods=methods)

    sub = Starlette(routes=[Route("/{name}", echo), Route("/x/{n:int}", echo)])
    routes = [r(f"/static{i}/info") for i in range(6)]
    routes += [
        r("/items/{item_id:int}"), r("/items/{name}", ["GET", "POST"]), r("/files/{p:path}"),
        r("/u/{uid:uuid}"), r("/m/{x:float}"), r("/ping", ["GET"]), r("/users/{uid}/posts/{pid:int}", ["GET", "DELETE"]),
        r("/trail/"), r("/notrail"), r("/v{ver}/health"), Mount("/sub", app=sub), r("/{catchall:path}", ["PUT"]),
    ]
    return routes


def build_starlette():
    return Starlette(routes=make_routes_for_starlette())


def build_fastapi():
    app = FastAPI()

    @app.get("/")
    async def root():
        return {"ok": True}

    for i in range(6):
        app.add_api_route(f"/static{i}/info", lambda i=i: {"i": i}, methods=["GET"])

    @app.get("/items/{item_id}")
    async def item(item_id: int):
        return {"item_id": item_id, "type": type(item_id).__name__}

    @app.post("/items/{name}")
    async def item_post(name: str):
        return {"name": name}

    @app.get("/files/{p:path}")
    async def files(p: str):
        return {"p": p}

    @app.get("/u/{uid}")
    async def u(uid: __import__("uuid").UUID):
        return {"uid": str(uid)}

    router = APIRouter(prefix="/v1", tags=["v1"])

    @router.get("/things/{tid}")
    async def thing(tid: int):
        return {"tid": tid}

    @router.delete("/things/{tid}")
    async def thing_del(tid: int):
        return {"deleted": tid}

    app.include_router(router)
    inner = APIRouter()

    @inner.get("/deep/{a}/{b:int}")
    async def deep(a: str, b: int):
        return {"a": a, "b": b}

    app.include_router(inner, prefix="/nest")

    async def plain(request: Request):
        return PlainTextResponse("mounted " + request.path_params.get("rest", ""))

    app.mount("/m", Starlette(routes=[Route("/{rest:path}", plain)]))
    return app


def snapshot(resp):
    return (resp.status_code, resp.headers.get("location"), resp.headers.get("allow"),
            resp.headers.get("content-type"), resp.text)


PATHS = [
    "/", "/static0/info", "/static5/info", "/static9/info", "/items/42", "/items/abc", "/items/", "/items",
    "/items/99999999999999999999999", "/files/a/b/c.txt", "/files/", "/files", "/u/123e4567-e89b-12d3-a456-426614174000",
    "/u/nope", "/m/3.14", "/m/3", "/m/x", "/ping", "/ping/", "/users/alice/posts/7", "/users/alice/posts/x",
    "/trail", "/trail/", "/notrail", "/notrail/", "/v2/health", "/vX/health", "/sub/hello", "/sub/x/5", "/sub/x/z",
    "/sub", "/sub/", "/anything/else", "/v1/things/3", "/v1/things/x", "/nest/deep/a/9", "/nest/deep/a/q",
    "/m/foo/bar", "/m/", "/m", "/%E3%81%82", "/static0", "//", "/a//b", "/items/あ",
]
METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"]


def compare(builder, name, rng, n_random=400):
    base = TestClient(builder(), follow_redirects=False)
    fast_app = builder()
    accelerate(fast_app)
    fast = TestClient(fast_app, follow_redirects=False)
    pairs = list(itertools.product(METHODS, PATHS))
    rng.shuffle(pairs)
    bad = 0
    for method, path in pairs[: max(n_random, len(pairs))]:
        a = snapshot(base.request(method, path))
        b = snapshot(fast.request(method, path))
        if a != b:
            bad += 1
            print("MISMATCH", name, method, path, "\n  base:", a, "\n  fast:", b)
    print("%s: %d requests compared, mismatches=%d" % (name, len(pairs), bad))
    return bad


def test_equivalence():
    rng = random.Random(1)
    assert compare(build_starlette, "starlette", rng) == 0
    assert compare(build_fastapi, "fastapi", rng) == 0


def test_actually_accelerated():
    app = build_starlette()
    accelerate(app)
    TestClient(app).get("/items/1")
    st = app.router.__dict__.get("_mfastapi_state")
    assert st is not None and st.table.size() == len(app.router.routes)
    assert getattr(type(app.router), "_mfastapi_accelerated", False)


def test_fastapi_actually_accelerated():
    app = build_fastapi()
    accelerate(app)
    TestClient(app).get("/items/1")
    st = app.router.__dict__.get("_mfastapi_state")
    assert st is not None and st.table.size() == len(app.router.routes), "FastAPI router was not accelerated"
    # include_routerで作られた内包ルーターはワイルドカード候補になり、近道(404即時)は使わない
    assert st.plain is False


def test_routes_added_after_accelerate():
    app = build_starlette()
    accelerate(app)
    c = TestClient(app)
    assert c.get("/late").status_code == 405 or c.get("/late").status_code in (404, 405)
    app.router.routes.insert(0, Route("/late", lambda request: PlainTextResponse("late")))
    assert c.get("/late").text == "late"


if __name__ == "__main__":
    test_equivalence()
    test_actually_accelerated()
    test_fastapi_actually_accelerated()
    test_routes_added_after_accelerate()
    print("OK")
    sys.exit(0)
