# mfastapi

Mojo Support for Python's FastAPI. (FastAPI の Python + Rust + C++ 互換、Mojo 対応)

設計: [DESIGN.md](DESIGN.md)。本家: https://fastapi.tiangolo.com/ ・ https://github.com/fastapi/fastapi

## 現状(2026-11-14、段階Aの最小実装)
- `mfastapi.collect_ir(app)`: FastAPIアプリのルート表(IR、JSON直列化可)を取り出す。`include_router`、`Depends`の再帰、path/query/header/cookie/bodyに対応。
- `mfastapi.ir_to_openapi_skeleton(ir)` と `mfastapi.diff_openapi(openapi, skeleton)`: 本家 `/openapi.json` との互換差分テスト(パス・メソッド・パラメータ・本文有無)。
- `mojo/mfastapi_native.mojo`: `PythonModuleBuilder`による最小のMojo拡張(`add`、パス照合`path_matches`)。WSL上のMojo 1.3.0.dev2026111316でビルドし、Pythonから呼べることをpytest 2件で確認。
- 未実装: Rustサーバー、段階B/C、スキーマ本体(型)の比較。`mfastapi_native.mojo`の`path_matches`は初期の簡易版でStarlette非互換(互換版は下記のC ABI版)。

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

## 対応OS(ネイティブ層)
Mojoの公式対応はLinux(x86-64/ARM64)・macOS(Apple silicon)で、Windowsは**WSL経由のみ**(ネイティブ対応は予告段階)。Android・iOSの記載は見つからなかった。
そのためネイティブ層は **同じC ABIを2つの実装で提供**する: Mojo版(`mojo/mfastapi_cabi.mojo`)と、どこでも動く移植用C版(`c/mfastapi_cabi.c`、C99、C標準ライブラリのみ)。Pythonからは`native.py`(ctypes)が同じ名前で探して読む。

| OS | 使う実装 | 状態(この環境での実測) |
|---|---|---|
| Linux (x86-64) | Mojo / C | **確認済み**: 両実装でPython 2.7・3.12のテスト成功、2実装のパリティ(ランダム20万件)一致 |
| Windows 10/11 | C(MSVC) | **確認済み**: `scripts/build-windows.ps1`で x64(Python 3.13)・x86(Python 3.14 32bit)のDLLが成功。Mojoは**WSL経由のみ** |
| Android | C(NDK clang) | **ビルドのみ確認**: arm64-v8a / armeabi-v7a / x86_64 / x86 の`libmfastapi.so`を生成(ELFの機種を確認)。実機・エミュレータでの**実行は未確認**。Chaquopy等のPythonランタイムから名前でロードする想定 |
| macOS | Mojo(Apple silicon) / C | **未確認**(macOS機が無い)。`CMakeLists.txt`のC版か`mojo build --emit shared-lib` |
| iOS / iPhone | C(静的ライブラリ) | **未確認**(Xcode無し)。`cmake -DCMAKE_SYSTEM_NAME=iOS`で`mfastapi_static`を作りアプリへリンクする設計。iOSではPythonも組み込み(BeeWare等)が必要でctypesの制約あり |
| FreeBSD等のUnix | C | **未確認**(`CMakeLists.txt`で`.so`を作る想定) |

```bash
wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/test-cross-wsl.sh   # Linux: C版+Mojo版、Python 2.7/3.xとパリティ
.\scriptsuild-windows.ps1                                       # Windows (PowerShell)
bash scripts/build-android.sh                                      # Android NDK (4 ABI、build/android/)
```
注意: ここでの「対応」は**ネイティブ関数(パス照合など)の呼び出し**までで、FastAPI本体(Python 3専用)をAndroid・iOSで動かすことは含まない。

## Starletteとの突き合わせと性能(2026-11-14実測、Starlette 1.8.0)
**調査(Starletteのソース)**: `compile_path()`はテンプレートを正規表現`^...$`にして`re.match`する。`{name}`/`{name:str}`=`[^/]+`、`:path`=`.*`、`:int`=`[0-9]+`、`:float`=`[0-9]+(\.[0-9]+)?`、`:uuid`=8-4-4-4-12の16進(`-`省略可)。パラメータは区間の途中にも置け、`re`と同じ貪欲+バックトラック。不正な`{`はリテラル、未知の型名は`assert`で拒否。`$`は末尾の改行1つ手前でも一致する。

**差分ファジング**(`bench/diff_starlette.py`: ランダムなテンプレート×パス、`starlette.routing.compile_path`を正解とする):
- 最初の実装(区間単位のみ): 比較86,612件中 **13,970件(16%)が不一致**(型指定・区間内パラメータ・波括弧)。
- Starlette互換に作り直し後(C版・Mojo版とも): 25.9万件×3回の乱数で**不一致0**。途中で見つかった差: Starletteは**コードポイント単位**なので、UTF-8の途中でパラメータを区切ると誤一致(`/{y}{x}`と`/٣`)→境界で区切らないよう修正。
- 未対応/差の残る点: パラメータ名の重複(Starletteは`ValueError`)の検出、ホスト用テンプレート(`/`で始まらない)、Starletteの独自コンバータ登録。バックトラック爆発は上限(20万ステップ)で`-2`(Pythonでは`RuntimeError`)にして断念する(Starletteの`re`は上限なし)。

**性能**(`bench/bench_match.py`、Python 3.12・WSL Ubuntu、1回の探索あたりのns。Starlette=コンパイル済み正規表現を順に`match`):

| ルート数 | 当たる位置 | Starlette | ネイティブ1件ずつ | ネイティブ一括(C版) | 一括(Mojo版) |
|---|---|---|---|---|---|
| 10 | 先頭 | 483 | 1700 | 1435 (0.3倍) | 1478 (0.3倍) |
| 50 | 末尾 | 11,957 | 85,363 | 2,975 (4.0倍) | 3,458 (3.4倍) |
| 200 | 末尾/外れ | 46,727 / 44,411 | 343,921 / 332,701 | 6,732 / 5,831 (7.6倍) | 10,264 / 9,399 (4.4倍) |

- **結論(正直に)**: 照合の中身そのものは速い(C版で約22ns/ルート、Starletteは約220ns/ルート=約10倍)。しかし**ctypesの呼び出し固定費が約0.7〜0.9µs**あり、先頭付近で当たる探索や1件ずつの呼び出しでは**Starletteより遅い**(0.3倍)。得をするのは、ルートが多く(≥約30)深く探す場合の**一括呼び出し**(`route_first_match`)で3〜8倍。
- 呼び出し固定費の実測(`bench/bench_overhead.py`、`add(2,3)`): 純Python演算25ns / ctypes 735〜916ns / **MojoのPythonModuleBuilder拡張 141ns**。→ 先頭ヒットでもStarlette(約480ns)に勝つには、一括照合を拡張モジュール版(Python 3専用)で提供するのが筋(未実装)。ctypes版(Python 2/他OS)は大きなルート表向け。
- Mojo版はC版より約1.5〜2倍遅い(構造体経由の読み出し等、最適化は未着手)。測定はこの1台・Linux(WSL)のみ。Windows/Android/macOSの速度は未測定。
- 本物のStarletteは照合の後に`scope`の更新やパラメータ変換(`convert`)も行うため、実アプリでの全体の速度向上はこの表より小さい。
