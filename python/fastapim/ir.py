"""FastAPIアプリのルート表(IR)を取り出す。IRはJSON直列化できる辞書のみで構成する。"""
from __future__ import annotations

from typing import Any

from fastapi import FastAPI
from fastapi.routing import APIRoute

IR_VERSION = 1


def _walk(dep):
    """Dependsで連なる依存関係を再帰的にたどる(本家のOpenAPIも同様に集約する)。"""
    yield dep
    for sub in dep.dependencies:
        yield from _walk(sub)


def _params(route: APIRoute) -> list[dict[str, Any]]:
    seen: dict[tuple[str, str], dict[str, Any]] = {}
    for d in _walk(route.dependant):
        for loc, items in (
            ("path", d.path_params),
            ("query", d.query_params),
            ("header", d.header_params),
            ("cookie", d.cookie_params),
        ):
            for p in items:
                name = p.alias or p.name
                seen[(loc, name)] = {"name": name, "in": loc, "required": bool(p.field_info.is_required())}
    return sorted(seen.values(), key=lambda x: (x["in"], x["name"]))


def _has_body(route: APIRoute) -> bool:
    return any(d.body_params for d in _walk(route.dependant))


def _iter_api_routes(app: FastAPI):
    """(実効パス, APIRoute)を列挙する。新しいFastAPIのinclude_router(実行時に展開)にも対応。"""
    try:
        from fastapi.routing import iter_route_contexts
    except ImportError:  # 旧版: app.routesに展開済みのAPIRouteが並ぶ
        for r in app.routes:
            if isinstance(r, APIRoute):
                yield r.path, r
        return
    for ctx in iter_route_contexts(app.routes):
        if isinstance(ctx.route, APIRoute):
            yield ctx.path, ctx.route


def collect_ir(app: FastAPI) -> dict[str, Any]:
    routes = []
    for path, r in _iter_api_routes(app):
        if not r.include_in_schema:
            continue
        routes.append(
            {
                "path": path,
                "methods": sorted(m for m in r.methods if m != "HEAD" or r.methods == {"HEAD"}),
                "name": r.name,
                "status_code": r.status_code or 200,
                "params": _params(r),
                "has_body": _has_body(r),
                "tags": list(r.tags or []),
            }
        )
    return {"ir_version": IR_VERSION, "title": app.title, "routes": routes}


def ir_to_openapi_skeleton(ir: dict[str, Any]) -> dict[str, Any]:
    """IRからOpenAPIの骨格(パス・メソッド・パラメータ)を生成する。スキーマ本体は未対応。"""
    paths: dict[str, Any] = {}
    for r in ir["routes"]:
        for m in r["methods"]:
            paths.setdefault(r["path"], {})[m.lower()] = {
                "parameters": [
                    {"name": p["name"], "in": p["in"], "required": p["required"]} for p in r["params"]
                ],
                "has_body": r["has_body"],
            }
    return {"title": ir["title"], "paths": paths}
