# -*- coding: utf-8 -*-
"""段階Cサーバー(純Mojo)と同じ経路を、FastAPI + Mojo関数(段階A+)で提供する比較用アプリ。
  PYTHONPATH=<fastapim_handlers.so>:<repo>/python uvicorn --app-dir examples server_ab:app"""
import fastapim_handlers as h
from fastapi import FastAPI

from fastapim import mojo_endpoint

app = FastAPI()


@app.get("/health")
async def health():
    return {"status": "ok"}


app.add_api_route("/mojo/health", health, methods=["GET"])
app.add_api_route("/mojo/fib/{n}", mojo_endpoint(h.fib, {"n": int}, returns=int, name="fib"), methods=["GET"])
app.add_api_route("/mojo/primes", mojo_endpoint(h.count_primes, {"n": (int, 1000)}, returns=int, name="primes"), methods=["GET"])
app.add_api_route("/mojo/words", mojo_endpoint(h.word_count, {"text": str}, returns=int, name="words"), methods=["GET"])
