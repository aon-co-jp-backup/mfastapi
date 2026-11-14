# -*- coding: utf-8 -*-
"""段階A+: Mojoで書いた関数を、FastAPIのエンドポイントとしてそのまま登録する橋渡し。

FastAPIは関数のシグネチャ(引数名・型・既定値)から、パス/クエリ/本文の取り出し・検証(Pydantic)・OpenAPI生成を行う。
Mojo拡張の関数にはシグネチャが無いので、宣言したシグネチャを持つ薄いPythonの関数でくるんで渡す。検証・依存関係・OpenAPI・
`/docs` は本家FastAPIのまま、中身の計算だけがMojo。

    import fastapim_handlers as h
    app.add_api_route("/fib/{n}", mojo_endpoint(h.fib, {"n": int}, returns=int), methods=["GET"])
    app.add_api_route("/primes", mojo_endpoint(h.count_primes, {"n": (int, 1000)}, returns=int))   # クエリ n(既定1000)

制限: Mojo関数の実行中はGILを保持する(同じプロセスの他のPythonスレッドは止まる)。長い計算は別ワーカー/プロセスで。
"""
import inspect

try:  # fastapi があれば、Mojo側の例外をHTTPエラーにする
    from fastapi import HTTPException
except ImportError:  # pragma: no cover
    HTTPException = None

__all__ = ["mojo_endpoint"]


def mojo_endpoint(fn, params, returns=None, name=None, error_status=400):
    """Mojo(など)の関数 fn を FastAPI のエンドポイント関数へ変換する。

    params: {引数名: 型} または {引数名: (型, 既定値)}。順序は fn の位置引数の順。FastAPI の `Query(...)` などを既定値に渡してもよい。
    returns: 戻り値の型(response_modelの推定・OpenAPIの応答スキーマに使われる)。
    fn が例外を投げた(Mojoの raise)場合は HTTP error_status(既定400)、fastapi が無ければ ValueError。"""
    names = list(params)
    plist = []
    for n in names:
        spec = params[n]
        if isinstance(spec, tuple):
            ann, default = spec
            plist.append(inspect.Parameter(n, inspect.Parameter.POSITIONAL_OR_KEYWORD, annotation=ann, default=default))
        else:
            plist.append(inspect.Parameter(n, inspect.Parameter.POSITIONAL_OR_KEYWORD, annotation=spec))
    # 既定値のある引数は後ろへ(Pythonの規則)。呼び出し順は names のまま。
    plist.sort(key=lambda p: p.default is not inspect.Parameter.empty)

    def endpoint(**kwargs):
        try:
            return fn(*[kwargs[n] for n in names])
        except Exception as e:  # Mojoの raise は Python の例外として届く
            if HTTPException is not None:
                raise HTTPException(status_code=error_status, detail=str(e))
            raise ValueError(str(e))

    endpoint.__signature__ = inspect.Signature(
        plist, return_annotation=returns if returns is not None else inspect.Signature.empty)
    endpoint.__name__ = name or getattr(fn, "__name__", "mojo_endpoint")
    endpoint.__doc__ = getattr(fn, "__doc__", None)
    if returns is not None:
        endpoint.__annotations__ = dict((p.name, p.annotation) for p in plist)
        endpoint.__annotations__["return"] = returns
    return endpoint
