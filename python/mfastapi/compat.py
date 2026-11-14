"""本家FastAPIの /openapi.json とIR由来の骨格を比較し、差分の一覧を返す(空なら一致)。"""
from __future__ import annotations

from typing import Any


def _normalize(openapi: dict[str, Any]) -> dict[str, Any]:
    paths: dict[str, Any] = {}
    for path, ops in openapi.get("paths", {}).items():
        for method, op in ops.items():
            if method not in {"get", "put", "post", "delete", "options", "head", "patch", "trace"}:
                continue
            paths.setdefault(path, {})[method] = {
                "parameters": sorted(
                    ({"name": p["name"], "in": p["in"], "required": bool(p.get("required", False))}
                     for p in op.get("parameters", [])),
                    key=lambda x: (x["in"], x["name"]),
                ),
                "has_body": "requestBody" in op,
            }
    return {"title": openapi.get("info", {}).get("title"), "paths": paths}


def diff_openapi(reference: dict[str, Any], skeleton: dict[str, Any]) -> list[str]:
    ref = _normalize(reference)
    diffs: list[str] = []
    if ref["title"] != skeleton["title"]:
        diffs.append(f"title: {ref['title']!r} != {skeleton['title']!r}")
    for path in sorted(set(ref["paths"]) | set(skeleton["paths"])):
        a, b = ref["paths"].get(path), skeleton["paths"].get(path)
        if a is None or b is None:
            diffs.append(f"path {path}: only in {'skeleton' if a is None else 'reference'}")
            continue
        for m in sorted(set(a) | set(b)):
            if a.get(m) != b.get(m):
                diffs.append(f"{m.upper()} {path}: {a.get(m)} != {b.get(m)}")
    return diffs
