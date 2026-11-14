# -*- coding: utf-8 -*-
"""段階B・C(MojoのHTTPサーバー)が、FastAPI+Mojo関数版と同じ422エラー形式・OpenAPI・応答を返すことをHTTPで確かめる。
使い方: python test_mojo_server_compat.py <MojoサーバーのURL(例 http://127.0.0.1:8801)> [prefix]
FastAPI側は同じディレクトリの test_endpoint.build(True) をインプロセスで呼ぶ(要 PYTHONPATH に fastapim_handlers と fastapim)。
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


# 基準のFastAPIは本物のHTTPサーバー(uvicorn)で動かす(TestClientはパスの%25を二重に復号し「.」を正規化するため基準に向かない)
import threading
import time
import uvicorn

_ref_app = t.build(True) if MODE == "c" else build_ref_b()
_srv = uvicorn.Server(uvicorn.Config(_ref_app, host="127.0.0.1", port=8899, log_level="error"))
threading.Thread(target=_srv.run, daemon=True).start()
for _ in range(100):
    if _srv.started:
        break
    time.sleep(0.1)


class _Ref:
    def get(self, path):
        class R:
            pass
        c = http.client.HTTPConnection("127.0.0.1", 8899, timeout=30)
        c.request("GET", path)
        r = c.getresponse()
        o = R()
        o.status_code, o.text = r.status, r.read().decode("utf-8")
        return o


fa = _Ref()
CASES_B = [
    "/py/hello/Taro", "/py/hello/%E3%81%82%E3%81%84", "/py/fib/10", "/py/fib/abc", "/py/fib/99", "/py/fib/-1",
    "/py/stats?csv=1,2,3.5", "/py/stats", "/fib/20", "/fib/x", "/fib/46", "/nope",
]
CASES = CASES_B if MODE == "b" else [
    "/fib/0", "/fib/20", "/fib/abc", "/fib/-3", "/fib/1.5", "/fib/%205%20", "/fib/5.0", "/fib/1_0", "/fib/1__0", "/fib/5.", "/fib/+7", "/fib/007", "/fib/1e1", "/fib/%E3%81%82", "/fib/46",
    "/primes", "/primes?n=100", "/primes?n=x", "/primes?n=", "/primes?n=%22q%22",
    "/words?text=hello%20big%20world", "/words?text=", "/words", "/words?text=%E6%97%A5%E6%9C%AC%20%E8%AA%9E",
    "/nope",
]
import random
import urllib.parse as _up

# 差分ファジング: 整数パラメータに様々な文字列を与え、FastAPIとステータス・本文が一致するか(seed固定)
_rnd = random.Random(20261114)
_ALPHA = "0123456789 +-_.eE" + chr(9) + chr(233) + chr(1635) + "abx%"
_FUZZ = ["".join(_rnd.choice(_ALPHA) for _ in range(_rnd.randint(0, 7))) for _ in range(400)]
_FUZZ += ["0", "-0", "+0", "00", "1_0", "1_", "_1", "1__0", "5.0", "5.", ".5", "5.0.0", " 5", "5 ", chr(9) + "5" + chr(10), "1e1", "+-1", "--1", "1 2", "%", chr(1635)]
_PFX = "/fib/" if MODE == "c" else "/py/fib/"
CASES = CASES + [_PFX + _up.quote(x, safe="") for x in _FUZZ if x != ""]
if MODE == "c":  # クエリのint・str(重複キー・空・+やエンコードも)
    CASES += ["/primes?n=" + _up.quote(x, safe="") for x in _FUZZ]
    CASES += ["/words?text=" + _up.quote(x, safe="") for x in _FUZZ[:100]]
    CASES += ["/primes?n=5&n=7", "/primes?n=x&n=7", "/primes?n=7&n=x", "/primes?n", "/primes?&&n=3&", "/primes?n=4#frag", "/words?text&text=a", "/words?t%65xt=hi", "/primes?n=%2B5", "/primes?n=+5", "/words?text=a+b", "/words?text=a%2Bb", "/words?other=1", "/primes?x=1&n=9"]
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
oa = _ref_app.openapi()
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
sys.exit(1 if bad or bad2 else 0)  # uvicornスレッドはdaemon
