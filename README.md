# mfastapi

Mojo Support for Python's FastAPI. (FastAPI の Python + Rust + C++ 互換、Mojo 対応)

設計: [DESIGN.md](DESIGN.md)。本家: https://fastapi.tiangolo.com/ ・ https://github.com/fastapi/fastapi

## 現状(2026-11-14、段階Aの最小実装)
- `mfastapi.collect_ir(app)`: FastAPIアプリのルート表(IR、JSON直列化可)を取り出す。`include_router`、`Depends`の再帰、path/query/header/cookie/bodyに対応。
- `mfastapi.ir_to_openapi_skeleton(ir)` と `mfastapi.diff_openapi(openapi, skeleton)`: 本家 `/openapi.json` との互換差分テスト(パス・メソッド・パラメータ・本文有無)。
- 未実装: Rustサーバー、Mojo拡張、段階B/C、スキーマ本体(型)の比較。Mojo・Rustはまだ一行も入っていない。

## テスト
```bash
python -m pip install fastapi pytest
python -m pytest -q tests
```
確認環境: Python 3.14, FastAPI 0.143.3, Pydantic 2.14.1(3件成功)。
新しいFastAPIは`include_router`を実行時に展開するため`fastapi.routing.iter_route_contexts`を使う(旧版は`app.routes`へフォールバック)。
