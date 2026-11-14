# mfastapi

Mojo Support for Python's FastAPI. (FastAPI の Python + Rust + C++ 互換、Mojo 対応)

設計: [DESIGN.md](DESIGN.md)。本家: https://fastapi.tiangolo.com/ ・ https://github.com/fastapi/fastapi

## 現状(2026-11-14、段階Aの最小実装)
- `mfastapi.collect_ir(app)`: FastAPIアプリのルート表(IR、JSON直列化可)を取り出す。`include_router`、`Depends`の再帰、path/query/header/cookie/bodyに対応。
- `mfastapi.ir_to_openapi_skeleton(ir)` と `mfastapi.diff_openapi(openapi, skeleton)`: 本家 `/openapi.json` との互換差分テスト(パス・メソッド・パラメータ・本文有無)。
- `mojo/mfastapi_native.mojo`: `PythonModuleBuilder`による最小のMojo拡張(`add`、パス照合`path_matches`)。WSL上のMojo 1.3.0.dev2026111316でビルドし、Pythonから呼べることをpytest 2件で確認。
- 未実装: Rustサーバー、段階B/C、スキーマ本体(型)の比較。`path_matches`はStarletteの照合との突き合わせ・性能実測がまだ(型指定`{x:int}`や`{p:path}`も未対応)。

## テスト
```bash
python -m pip install fastapi pytest
python -m pytest -q tests
```
確認環境: Python 3.14, FastAPI 0.143.3, Pydantic 2.14.1(3件成功)。
新しいFastAPIは`include_router`を実行時に展開するため`fastapi.routing.iter_route_contexts`を使う(旧版は`app.routes`へフォールバック)。

## Mojo拡張(WSL)
```bash
wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/setup-mojo-wsl.sh   # 初回: uv + Mojo(nightly)導入
wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/build-mojo-wsl.sh   # ビルド + tests/mojo 実行
```
PowerShellから実行する(Git Bashは`/mnt/...`を書き換える。Windows側PATHの括弧で壊れるため、必ずスクリプト経由)。
Mojoの構文はnightlyで変わる(`len(String)`不可→`byte_length()`など)。版は`setup-mojo-wsl.sh`で固定していないため要注意。

## Python 2 / 3 の両方から呼ぶ(C ABI + ctypes)
- `mojo/mfastapi_cabi.mojo`: C ABI(`mfastapi_abi_version` / `mfastapi_add` / `mfastapi_path_matches`)の共有ライブラリ。Python C APIに依存しないため版を問わない(静的リンクで`ldd`上の依存なし)。
- `python/mfastapi/native.py`: ctypesの薄いラッパー(Python 2.7/3.x構文の共通部分のみ)。ライブラリは`MFASTAPI_LIB`または同ディレクトリの`libmfastapi.so`から探す。
- 確認(WSL, Linux x86_64): Python **2.7.18 / 3.9 / 3.12 / 3.14** で `tests/mojo/test_cabi.py` が成功。
```bash
wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/build-py27-wsl.sh   # 検証用のPython 2.7を~/py27へ(任意)
wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/test-cabi-wsl.sh    # ビルド+2.7/3.xで実行
```
**制限(重要)**: 本家FastAPI・Pydantic・Starletteは**Python 3専用**なので、Python 2から使えるのは`native.py`のネイティブ関数(パス照合など)だけ。FastAPIアプリのIR収集(`collect_ir`)はPython 3のみ。
Python 2はEOL(2020)のため検証用に限り、Python 2.7のビルドにはモダンGCC向けに`-std=gnu11`が必要だった。未確認: Windows(`.dll`)・macOS、Mojo拡張(PythonModuleBuilder版)との性能比較。
