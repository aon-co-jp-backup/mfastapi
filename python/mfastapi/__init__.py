"""mfastapi: FastAPI互換アプリを中間表現(IR)へ取り出し、Mojo/Rust層へ渡すための入口(段階A)。"""
from .ir import collect_ir, ir_to_openapi_skeleton
from .compat import diff_openapi
from .accel import accelerate

__all__ = ["collect_ir", "ir_to_openapi_skeleton", "diff_openapi", "accelerate"]
__version__ = "0.0.1"
