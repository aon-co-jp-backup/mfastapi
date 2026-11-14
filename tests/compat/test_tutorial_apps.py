"""本家FastAPIチュートリアル相当のアプリで、IR由来の骨格が /openapi.json と一致することを確認する。"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "python"))

import json
from typing import Annotated
from fastapi import APIRouter, Cookie, Depends, FastAPI, Header, Query
from pydantic import BaseModel
from mfastapi import collect_ir, diff_openapi, ir_to_openapi_skeleton


class Item(BaseModel):
    name: str
    price: float


def build_app() -> FastAPI:
    app = FastAPI(title="tutorial")
    router = APIRouter(prefix="/v1", tags=["items"])

    def common(q: str | None = None, limit: Annotated[int, Query(ge=1)] = 10):
        return {"q": q, "limit": limit}

    @app.get("/")
    async def root():
        return {"ok": True}

    @router.get("/items/{item_id}")
    def read(item_id: int, c: Annotated[dict, Depends(common)], ua: Annotated[str | None, Header()] = None):
        return {"id": item_id}

    @router.post("/items", status_code=201)
    def create(item: Item, session: Annotated[str | None, Cookie()] = None):
        return item

    @router.put("/items/{item_id}")
    def update(item_id: int, item: Item, required_q: str = Query()):
        return item

    app.include_router(router)
    return app


def test_ir_matches_reference_openapi():
    app = build_app()
    ir = collect_ir(app)
    json.dumps(ir)  # JSON直列化できること
    assert diff_openapi(app.openapi(), ir_to_openapi_skeleton(ir)) == []


def test_ir_contents():
    ir = collect_ir(build_app())
    by = {(r["path"], tuple(r["methods"])): r for r in ir["routes"]}
    assert by[("/v1/items", ("POST",))]["status_code"] == 201
    assert by[("/v1/items", ("POST",))]["has_body"] is True
    read = by[("/v1/items/{item_id}", ("GET",))]
    assert {"name": "item_id", "in": "path", "required": True} in read["params"]
    assert {"name": "limit", "in": "query", "required": False} in read["params"]


def test_diff_detects_mismatch():
    app = build_app()
    sk = ir_to_openapi_skeleton(collect_ir(app))
    del sk["paths"]["/"]
    assert diff_openapi(app.openapi(), sk)
