# -*- coding: utf-8 -*-
"""段階B・C(MojoのHTTPサーバー)が、FastAPI+Mojo関数版と同じ422エラー形式・OpenAPI・応答を返すことをHTTPで確かめる。
使い方: python test_mojo_server_compat.py <MojoサーバーのURL(例 http://127.0.0.1:8801)> [prefix]
FastAPI側は同じディレクトリの test_endpoint.build(True) をインプロセスで呼ぶ(要 PYTHONPATH に mfastapi_handlers と mfastapi)。
prefix は Mojoサーバー側のパス接頭辞(段階Bの /py ではなく、Mojoネイティブの経路は空)。"""
import http.client
import json
import os
import sys
from urllib.parse import urlparse

sys.path.insert(0, os.path.dirname(__file__))
import test_endpoint as t  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

base = urlparse(sys.argv[1])
MODE = sys.argv[2] if len(sys.argv) > 2 else "c"  # c: 段階C(純Mojo) / b: 段階B(Mojo受け口+Pythonハンドラ)


def get(path):
    c = http.client.HTTPConnection(base.hostname, base.port, timeout=30)
    c.request("GET", path)
    r = c.getresponse()
    return r.status, r.read().decode("utf-8")


def build_ref_b():
    """段階Bと同じ経路・シグネチャのFastAPI(Pythonハンドラはexamples/pyhandlers.py)。"""
    from fastapi import FastAPI, Response
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "examples"))
    import pyhandlers as ph

    app = FastAPI()

    def j(x):
        return Response(content=x, media_type="application/json")

    def py_hello(name: str):
        return j(ph.greet(name))

    def py_fib(n: int):
        if n < 0 or n > 35:
            from fastapi import HTTPException
            raise HTTPException(status_code=400, detail="n must be between 0 and 35")
        return j(ph.fib(str(n)))

    def py_stats(csv: str):
        return j(ph.stats(csv))

    app.add_api_route("/py/hello/{name}", py_hello, methods=["GET"])
    app.add_api_route("/py/fib/{n}", py_fib, methods=["GET"])
    app.add_api_route("/py/stats", py_stats, methods=["GET"])
    app.add_api_route("/fib/{n}", t.build(True).router.routes[-4].endpoint, methods=["GET"])
    return app


fa = TestClient(t.build(True) if MODE == "c" else build_ref_b())
CASES_B = [
    "/py/hello/Taro", "/py/hello/%E3%81%82%E3%81%84", "/py/fib/10", "/py/fib/abc", "/py/fib/99", "/py/fib/-1",
    "/py/stats?csv=1,2,3.5", "/py/stats", "/fib/20", "/fib/x", "/fib/46", "/nope",
]
CASES = CASES_B if MODE == "b" else [
    "/fib/0", "/fib/20", "/fib/abc", "/fib/-3", "/fib/1.5", "/fib/%E3%81%82", "/fib/46",
    "/primes", "/primes?n=100", "/primes?n=x", "/primes?n=", "/primes?n=%22q%22",
    "/words?text=hello%20big%20world", "/words?text=", "/words", "/words?text=%E6%97%A5%E6%9C%AC%20%E8%AA%9E",
    "/nope",
]
bad = 0
for url in CASES:
    sa, ba = fa.get(url).status_code, fa.get(url).text
    sb, bb = get(url)
    try:
        same = sa == sb and json.loads(ba) == json.loads(bb)
    except ValueError:
        same = sa == sb == 404  # 404 本文の形式だけは別実装で異なる
    if not same:
        bad += 1
        print("DIFF", url, "\n  fastapi:", sa, ba, "\n  mojo:   ", sb, bb)
print("responses/422 bodies: %d cases, differences=%d" % (len(CASES), bad))

# OpenAPI: parameters / 200・422 スキーマの要点がFastAPIと一致するか
oa = (t.build(True) if MODE == "c" else build_ref_b()).openapi()
ob = json.loads(get("/openapi.json")[1])
bad2 = 0
OPEN_PATHS = ("/fib/{n}", "/primes", "/words") if MODE == "c" else ("/py/hello/{name}", "/py/fib/{n}", "/py/stats", "/fib/{n}")
for path in OPEN_PATHS:
    pa, pb = oa["paths"][path]["get"], ob["paths"][path]["get"]
    checks = {
        "parameters": pa.get("parameters") == pb.get("parameters"),
        "operationId": pa["operationId"] == pb["operationId"],
        "200 type": MODE == "b" or pa["responses"]["200"]["content"]["application/json"]["schema"]["type"]
        == pb["responses"]["200"]["content"]["application/json"]["schema"]["type"],
        "422 ref": pa["responses"]["422"] == pb["responses"]["422"],
    }
    for k, ok in checks.items():
        if not ok:
            bad2 += 1
            print("OPENAPI DIFF", path, k, "\n  fastapi:", pa.get("parameters"), pa["operationId"], "\n  mojo:   ", pb.get("parameters"), pb["operationId"])
for name in ("HTTPValidationError", "ValidationError"):
    if oa["components"]["schemas"][name] != ob["components"]["schemas"][name]:
        bad2 += 1
        print("OPENAPI DIFF schema", name, "\n ", oa["components"]["schemas"][name], "\n ", ob["components"]["schemas"][name])
print("openapi: openapi=%s paths compared=%d differences=%d" % (ob["openapi"], len(OPEN_PATHS), bad2))
st, page = get("/docs")
assert st == 200 and "swagger-ui" in page and "/openapi.json" in page, "/docs"
print("/docs served (Swagger UI)")
sys.exit(1 if bad or bad2 else 0)
