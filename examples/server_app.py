# -*- coding: utf-8 -*-
"""実サーバー(uvicorn)用のデモアプリ。ルート200本のFastAPI。
  uvicorn --app-dir examples server_app:app
MojoもC拡張も無い環境でも、そのまま(本家のルート探索で)動く。"""
import sys

from fastapi import FastAPI

import fastapim

app = FastAPI()
N = 200
for i in range(N):
    if i % 2:
        app.add_api_route("/api/v1/res%d/{rid}" % i, (lambda i: lambda rid: {"route": i, "rid": rid})(i), methods=["GET"])
    else:
        app.add_api_route("/svc%d/items" % i, (lambda i: lambda: {"route": i})(i), methods=["GET"])


@app.get("/files/{p:path}")
async def files(p: str):
    return {"p": p}


@app.get("/__backend")
async def which():
    return {"backend": fastapim.backend()}


fastapim.accelerate(app)
print("fastapim backend:", fastapim.backend(), file=sys.stderr)
