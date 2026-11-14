# -*- coding: utf-8 -*-
"""StarletteのRouter(およびその上に作られたFastAPI)のルート探索を、Mojo拡張のRouteTableで高速化する。

方針(安全第一): ルート探索の「候補の絞り込み」だけを置き換え、判定そのものは本家のコードに任せる。
  1. 受信パスで RouteTable.first_match_from を引いて、パスが合う候補ルートを番号順に得る(N個の正規表現を回さない)。
  2. 候補に対して本家の route.matches(scope) を呼ぶ(メソッド違いの PARTIAL=405、child_scope、path_params変換は本家のまま)。
  3. 最初の FULL が見つかれば、本家と同じ手順で処理する。
  4. FULL が無い(405・redirect_slashes・404・FastAPIの低優先度など)場合は、元の Router.app にそのまま任せる。
     → 例外的な経路の挙動は一切変えない(その分、そのときだけ全ルートを走査する本家の費用がかかる)。
テンプレートを持たないルート(Host、独自のBaseRoute、FastAPIの include_router 由来など)は「すべてのパスに一致する候補」
として表に入れ、本家の matches で最終判定する(絞り込みが過剰でも結果は変わらない)。

使い方: mfastapi.accelerate(app)   # Starlette / FastAPI のアプリ、または Router を渡す。要 Python 3 + mfastapi_native
"""
from __future__ import annotations

import warnings
from typing import Any

try:
    import mfastapi_native as _ext
except ImportError:  # pragma: no cover
    _ext = None

from starlette.routing import Match, Mount, Route, Router, WebSocketRoute

try:  # starlette 1.x
    from starlette._utils import get_route_path
except ImportError:  # pragma: no cover
    def get_route_path(scope):  # type: ignore
        return scope["path"]

MIN_ROUTES = 8  # これ未満のルート数では、本家の逐次走査のほうが速い(実測)ので何もしない
_WILDCARD = "{x:path}"


def _template_of(route: Any) -> str:
    """そのルートがパスで一致しうる条件を表すテンプレート(絞り込みは過剰でよいが不足してはならない)。"""
    # 型を厳密に見る(サブクラスは matches を上書きしている可能性があるので、本家3種だけテンプレート化する)。
    t = type(route)
    if t is Route or t is WebSocketRoute:
        return route.path
    if t is Mount:
        return route.path + "/{path:path}"
    # FastAPIのAPIRoute/WebSocketRoute系は path 属性を持ち、matches は Route 相当(child_scope に route を足すだけ)
    mod = getattr(t, "__module__", "")
    if mod.startswith("fastapi.") and t.__name__ in ("APIRoute", "APIWebSocketRoute") and hasattr(route, "path"):
        return route.path
    return _WILDCARD


class _State:
    __slots__ = ("table", "routes", "n", "plain")

    def __init__(self, routes):
        self.routes = list(routes)
        self.n = len(self.routes)
        templates = [_template_of(r) for r in self.routes]
        # 近道(候補なし→404)を使ってよいのは、本家の Router.app がStarlette素のもので、かつ全ルートがテンプレート化できる場合だけ
        self.plain = all(t != _WILDCARD for t in templates)
        try:
            self.table = _ext.RouteTable(templates)
        except Exception:
            # 本家が受け付けるテンプレートを拒否した場合など。何も壊さないよう全ルートをワイルドカードにする。
            self.table = _ext.RouteTable([_WILDCARD] * len(self.routes))


def _make_app(original_app, mode):
    """mode: 1=Starlette素のRouter, 2=FastAPIのAPIRouter(_route_selectedあり), 0=その他(絞り込みのみ・処理は本家へ)"""

    async def app(self, scope, receive, send):
        routes = self.routes
        typ = scope["type"]
        if (typ == "http" or typ == "websocket") and len(routes) >= MIN_ROUTES:
            st = self.__dict__.get("_mfastapi_state")
            if st is None or st.n != len(routes) or st.routes[-1] is not routes[-1]:
                st = self.__dict__["_mfastapi_state"] = _State(routes)
            if "router" not in scope:
                scope["router"] = self
            # get_route_path と同じ結果(root_pathが空なら scope["path"] そのもの)
            path = scope["path"] if not scope.get("root_path") else get_route_path(scope)
            find = st.table.first_match_from
            i = find(path, 0)
            if i < 0 and mode == 1 and st.plain:
                # 候補が1つも無い = 本家の探索ではどのルートも FULL/PARTIAL にならない。
                # redirect_slashes の候補も無ければ、即404(default)。
                if typ != "http" or not self.redirect_slashes or path == "/":
                    return await self.default(scope, receive, send)
                alt = path.rstrip("/") if path.endswith("/") else path + "/"  # 本家の redirect_slashes と同じ変換
                if find(alt, 0) < 0:
                    return await self.default(scope, receive, send)
            while i >= 0:
                route = routes[i]
                match, child_scope = route.matches(scope)
                if match == Match.FULL:
                    if mode == 1:
                        scope["route"] = route
                        scope.update(child_scope)
                        return await route.handle(scope, receive, send)
                    if mode == 2:
                        scope.update(child_scope)
                        _route_selected(
                            scope=scope,
                            path=getattr(route, "path_format", None),
                            mount=isinstance(route, Mount),
                        )
                        return await route.handle(scope, receive, send)
                    break  # mode 0: 本家へ委ねる
                i = find(path, i + 1)
        return await original_app(self, scope, receive, send)

    return app


try:  # FastAPI 0.137以降の内部ヘルパ(テレメトリ用)。無ければFastAPIでは本家へ委ねる。
    from fastapi.routing import APIRouter as _APIRouter, _route_selected
except ImportError:  # pragma: no cover
    _APIRouter = None
    _route_selected = None


def accelerate(target: Any) -> Any:
    """Starlette/FastAPI のアプリ(または Router)のルート探索を高速化する。戻り値は同じオブジェクト。"""
    if _ext is None:
        warnings.warn("mfastapi_native extension not available; routing is not accelerated", RuntimeWarning)
        return target
    router = target if isinstance(target, Router) else getattr(target, "router", None)
    if not isinstance(router, Router):
        raise TypeError("accelerate() expects a Starlette/FastAPI app or a Router")
    cls = type(router)
    if getattr(cls, "_mfastapi_accelerated", False):
        return target
    original = cls.app
    if _APIRouter is not None and isinstance(router, _APIRouter) and _route_selected is not None:
        mode = 2
    elif type(router).__module__.startswith("starlette."):
        mode = 1
    else:
        mode = 0
    accel_cls = type(cls.__name__, (cls,), {"app": _make_app(original, mode), "_mfastapi_accelerated": True})
    router.__class__ = accel_cls
    # Router は __init__ で middleware_stack = self.app (束縛メソッド) を保持する。作り直す。
    ms = router.__dict__.get("middleware_stack")
    if ms is not None and getattr(ms, "__func__", None) is original:
        router.middleware_stack = router.app
    elif ms is not None:
        warnings.warn("router has middleware; acceleration applies to the inner router only", RuntimeWarning)
    return target
