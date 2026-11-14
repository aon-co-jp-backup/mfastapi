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
from starlette.routing import Mount, Route, WebSocketRoute

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


def _ws_results(app, paths):
    """各パスへWebSocket接続し、(受け取った文字列 or 拒否時の例外種別/コード)を集める。"""
    from starlette.websockets import WebSocketDisconnect

    c = TestClient(app)
    out = {}
    for p in paths:
        try:
            with c.websocket_connect(p) as ws:
                out[p] = ("ok", ws.receive_text())
        except WebSocketDisconnect as e:
            out[p] = ("disconnect", e.code)
        except Exception as e:  # 404など
            out[p] = ("error", type(e).__name__)
    return out


def _with_ws(app):
    from starlette.websockets import WebSocket

    async def hello(ws: WebSocket):
        await ws.accept()
        await ws.send_text("hello " + repr(sorted(ws.path_params.items())))
        await ws.close()

    for i in range(10):  # MIN_ROUTES以上にして加速を有効にする
        app.add_api_websocket_route("/wsdummy%d" % i, hello) if hasattr(app, "add_api_websocket_route") \
            else app.router.routes.append(WebSocketRoute("/wsdummy%d" % i, hello))
    if hasattr(app, "add_api_websocket_route"):
        app.add_api_websocket_route("/ws/{room}", hello)
    else:
        app.router.routes.append(WebSocketRoute("/ws/{room}", hello))
    return app


WS_PATHS = ["/ws/lobby", "/ws/", "/ws", "/wsdummy3", "/nope", "/ws/a/b", "/wsdummy99"]


def test_websocket_equivalence():
    for builder in (build_starlette, build_fastapi):
        base = _with_ws(builder())
        fast = accelerate(_with_ws(builder()))
        a, b = _ws_results(base, WS_PATHS), _ws_results(fast, WS_PATHS)
        assert a == b, (builder.__name__, a, b)
        assert a["/ws/lobby"][0] == "ok", a  # 実際に接続できていること(全部失敗の一致を防ぐ)
        print("websocket %s: %d paths equal" % (builder.__name__, len(WS_PATHS)))


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
    test_websocket_equivalence()
    test_routes_added_after_accelerate()
    print("OK")
    sys.exit(0)
