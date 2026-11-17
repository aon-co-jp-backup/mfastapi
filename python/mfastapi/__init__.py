"""mfastapi: FastAPI互換アプリを中間表現(IR)へ取り出し、Mojo/C層へ渡す入口と、Starlette/FastAPIのルート探索の高速化(accelerate)。

`accelerate` は Starlette だけで使える(fastapi不要)。IR/OpenAPI関連(collect_ir など)は fastapi が要るので、使うときに初めて読み込む。"""
from .accel import accelerate, backend
from .mojo import mojo_endpoint

__all__ = ["collect_ir", "ir_to_openapi_skeleton", "diff_openapi", "accelerate", "backend", "mojo_endpoint"]
try:  # 配布物の版(pyproject.toml)と一致させる
    from importlib.metadata import version as _v

    __version__ = _v("mfastapi")
except Exception:  # 未インストールの作業ツリーなど
    __version__ = "0"


def __getattr__(name):  # PEP 562: fastapi が無い環境でも `import mfastapi` と accelerate は使える
    if name in ("collect_ir", "ir_to_openapi_skeleton"):
        from . import ir
        return getattr(ir, name)
    if name == "diff_openapi":
        from . import compat
        return compat.diff_openapi
    raise AttributeError("module 'mfastapi' has no attribute %r" % name)
