# -*- coding: utf-8 -*-
"""段階A+: Mojo関数をFastAPIのエンドポイントとして登録し、純Pythonの同等関数と同じ応答・OpenAPI・エラーになることを確かめる。
実行: PYTHONPATH=<mfastapi_handlers.soのdir>:<repo>/python python tests/mojo_endpoint/test_endpoint.py (要 fastapi httpx)"""
import sys

from fastapi import FastAPI
from fastapi.testclient import TestClient

import mfastapi_handlers as h
from mfastapi import mojo_endpoint


def py_fib(n):
    return n if n < 2 else py_fib(n - 1) + py_fib(n - 2)


def py_primes(n):
    if n < 2:
        return 0
    s = [True] * (n + 1)
    s[0] = s[1] = False
    for i in range(2, int(n ** 0.5) + 1):
        if s[i]:
            for j in range(i * i, n + 1, i):
                s[j] = False
    return sum(s)


def py_words(t):
    return len(t.split())


def build(use_mojo):
    app = FastAPI()
    if use_mojo:
        app.add_api_route("/fib/{n}", mojo_endpoint(h.fib, {"n": int}, returns=int, name="fib"), methods=["GET"])
        app.add_api_route("/primes", mojo_endpoint(h.count_primes, {"n": (int, 1000)}, returns=int, name="primes"), methods=["GET"])
        app.add_api_route("/words", mojo_endpoint(h.word_count, {"text": str}, returns=int, name="words"), methods=["GET"])
        app.add_api_route("/mean", mojo_endpoint(h.mean, {"values": list[float]}, returns=float, name="mean"), methods=["POST"])
    else:
        def fib(n: int) -> int:
            return py_fib(n)

        def primes(n: int = 1000) -> int:
            return py_primes(n)

        def words(text: str) -> int:
            return py_words(text)

        def mean(values: list[float]) -> float:
            return sum(values) / len(values)

        app.add_api_route("/fib/{n}", fib, methods=["GET"])
        app.add_api_route("/primes", primes, methods=["GET"])
        app.add_api_route("/words", words, methods=["GET"])
        app.add_api_route("/mean", mean, methods=["POST"])
    return app


CASES = [
    ("GET", "/fib/0", None), ("GET", "/fib/1", None), ("GET", "/fib/20", None), ("GET", "/fib/abc", None),
    ("GET", "/primes", None), ("GET", "/primes?n=100", None), ("GET", "/primes?n=1", None), ("GET", "/primes?n=x", None),
    ("GET", "/words?text=hello%20big%20world", None), ("GET", "/words?text=", None), ("GET", "/words", None),
    ("POST", "/mean", [1, 2, 3.5]), ("POST", "/mean", ["a"]), ("POST", "/mean", "oops"),
]


def test_same_responses():
    a, b = TestClient(build(False)), TestClient(build(True))
    bad = 0
    for method, url, body in CASES:
        ra = a.request(method, url, json=body) if body is not None else a.request(method, url)
        rb = b.request(method, url, json=body) if body is not None else b.request(method, url)
        # 検証エラー(422)の本文はFastAPIが作るので完全一致するはず。値の応答も一致するはず。
        if (ra.status_code, ra.json()) != (rb.status_code, rb.json()):
            bad += 1
            print("MISMATCH", method, url, body, "\n  py:   ", ra.status_code, ra.text, "\n  mojo: ", rb.status_code, rb.text)
    print("same responses: %d cases, mismatches=%d" % (len(CASES), bad))
    assert bad == 0


def test_openapi_parameters_match():
    oa, ob = build(False).openapi(), build(True).openapi()
    for path in ("/fib/{n}", "/primes", "/words", "/mean"):
        for method in oa["paths"][path]:
            pa, pb = oa["paths"][path][method], ob["paths"][path][method]
            assert pa.get("parameters") == pb.get("parameters"), (path, pa.get("parameters"), pb.get("parameters"))
            assert pa.get("requestBody") == pb.get("requestBody"), path
            assert pa["responses"]["200"]["content"]["application/json"]["schema"] == \
                pb["responses"]["200"]["content"]["application/json"]["schema"], path
    print("openapi parameters/requestBody/response schema match for 4 endpoints")


def test_mojo_error_is_http_400():
    c = TestClient(build(True))
    r = c.get("/fib/46")  # Mojo側の範囲チェック(raise)
    assert r.status_code == 400 and "between" in r.json()["detail"], r.text
    print("mojo raise -> HTTP 400:", r.json()["detail"])


if __name__ == "__main__":
    test_same_responses()
    test_openapi_parameters_match()
    test_mojo_error_is_http_400()
    print("OK")
    sys.exit(0)
