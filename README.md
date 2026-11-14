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

## 拡張モジュール版の一括照合(Python 3専用、2026-11-14)
`mojo/mfastapi_native.mojo`(`PythonModuleBuilder`)に **`RouteTable`** を追加した。ルート登録時にテンプレートを一度だけ解析して(リテラルは連結、パラメータは種別コード化)保持し、`table.first_match(path)`が最初に一致した番号(なければ`-1`)を返す。`mojo/mfastapi_match.mojo`(照合の核)・`mojo/mfastapi_table.mojo`(コンパイル済み表)をC ABI版と共有する。
```python
import mfastapi_native as ext          # build: scripts/build-ext-wsl.sh
t = ext.RouteTable(["/", "/items/{id:int}", "/items/{name}"])
t.first_match("/items/7")   # -> 1
```
`mfastapi.native.make_table(templates)` は拡張があればそれ、無ければctypes版を返す(Python 2でも使える)。

**速さを出すために入れた工夫**(それぞれ実測で確認): ①ctypesをやめて拡張にし呼び出し固定費を0.74〜0.9µs→約0.14µsへ、②Pythonのstrが持つUTF-8バッファをCPythonから**コピーなしで**直接参照(`PyUnicode_AsUTF8AndSize`、1回あたり約80ns短縮)、③テンプレートを事前解析して毎回の再解析をなくす、④先頭のリテラルを関数呼び出し前にその場で比較して足切り、⑤末尾の`{str}`は取り切れたらバックトラックなしで一致。

**正しさ**: `bench/diff_table.py`(ランダムな表×パスをStarletteの正規表現と比較): Python 3.12・3.14で各16万件、**不一致0**。`scripts/test-ext-wsl.sh`で再現できる。

**性能**(`bench/bench_match.py`、Python 3.12・WSL、1回の探索あたりns。Starlette 1.8.0 = コンパイル済み正規表現を順に`match`):

| ルート数・当たる位置 | Starlette | ctypes一括 | **拡張 RouteTable** | 拡張の倍率 |
|---|---|---|---|---|
| 10・先頭 | 470 | 1,462 | **253** | 1.9倍 |
| 10・末尾 | 2,286 | 1,947 | **347** | 6.6倍 |
| 50・末尾 | 12,454 | 3,526 | **664** | 18.8倍 |
| 200・末尾 | 47,768 | 11,716 | **2,079** | 23.0倍 |
| 200・外れ | 47,210 | 8,665 | **1,292** | 36.5倍 |

先頭ヒットでもStarletteに勝つ(前回のctypes版は0.3倍=負け)。残る固定費は約230ns(Pythonのメソッド呼び出し約140ns+その他)で、これ以上はPython側の呼び出し機構の限界に近い。
注意: ①実アプリのStarletteは照合後に`scope`更新・パラメータ変換も行うため全体の改善はこの表より小さい。②この1台・Linux(WSL)・Python 3.12のみの測定。③パラメータ値の取り出しは下記の`match()`で対応。④Mojo拡張のためPython 2・Windowsネイティブ・Android・iOSでは使えない(ctypes/C版にフォールバック)。

### パラメータ値の取り出し `RouteTable.match`(2026-11-14)
`table.match(path)` は一致しなければ `None`、一致すれば `(ルート番号, path_params)` を返す。値はStarletteの`convertor.convert`と同じ型に変換する(`int`→`int`、`float`→`float`、`uuid`→`uuid.UUID`、`str`/`path`→`str`。19桁以上の整数はPythonの`int()`で変換)。
```python
t = ext.RouteTable(["/users/{uid}/posts/{pid:int}"])
t.match("/users/alice/posts/77")   # -> (0, {'uid': 'alice', 'pid': 77})
```
- 登録時に、パラメータ名の重複(Starletteと同じく`ValueError`相当)・17個以上のパラメータ・未知の型名を拒否する。
- 内部: 照合中に各パラメータの[開始,終端]を記録(バックトラックで上書きされ、成功した経路のものだけが残る)。パラメータ名のstrと`int`/`float`/`UUID`は表に保持し、毎回の`import`・文字列生成をなくした(これで`float`が0.7倍→1.6倍に改善)。
- **正しさ**: `bench/diff_table.py`が`match`の結果(値と**型**)をStarletteの`groupdict()`+`convert`と突き合わせ、Python 3.12・3.14で各16万件・不一致0。

**性能**(`bench/bench_params.py`、Python 3.12・WSL、Starlette = `match`+`groupdict`+`convert`、1回あたりns):

| ケース | Starlette | `ext.match` | 倍率 |
|---|---|---|---|
| 静的 `/health` | 811 | 436 | 1.9倍 |
| `/items/{id:int}` | 1,271 | 598 | 2.1倍 |
| `/users/{uid}/posts/{pid:int}` | 1,599 | 837 | 1.9倍 |
| `/files/{p:path}` | 1,132 | 643 | 1.8倍 |
| `/m/{x:float}` | 1,370 | 864 | 1.6倍 |
| `/u/{u:uuid}` | 3,377 | 2,953 | 1.1倍 |

`uuid`はPython標準の`uuid.UUID(...)`の生成自体が遅く(約2.5µs)、そこは両者共通のため差が出ない。値を取り出さない`first_match`(約250ns)に比べ`match`が約180ns遅いのは、結果の辞書とタプルの生成費用。

**(以前の判断: trie化は見送り → 下記のとおり実施した)** 当時の記述:: 200ルート末尾でも約3.5µs(1ルートあたり約17ns、Starletteの約13.6倍速い)で、効くのは数百〜数千ルートのときだけ。実装の複雑さ(順序を保つ候補集合の併合)に見合う利得が測れていないため、未実装。必要になったら`bench_match.py`のNを増やして再評価する。

## trie(先頭リテラルの木)化(2026-11-14)
`RouteTable`は、各ルートの先頭リテラルを**バイト単位のtrie**に載せる。検索は受信パスをたどりながら、経路上のノードに載っているルートだけを**番号の若い順に**試し、最小の番号を採用する(線形版と同じ結果)。ルートが8個以下なら線形のまま(木をたどるほうが遅いため)。途中で見つけた不具合: 後続の試行が失敗してもキャプチャ領域を上書きするため、採用したルートのキャプチャを別領域(`bcaps`)へ退避するようにした。
- **正しさ**: `bench/diff_table.py`を最大150ルートの表まで広げ、trie版・線形版・Starlette(+`first_match_from`)を突き合わせ、Python 3.12・3.14で各16万件・**不一致0**。
- **性能**(`bench/bench_match.py`、1回あたりns、Python 3.12・WSL):

| ルート数・位置 | Starlette | 線形 | **trie** | trieの対Starlette |
|---|---|---|---|---|
| 200・末尾 | 49,555 | 1,953 | **340** | 146倍 |
| 1000・末尾 | 244,514 | 6,660 | **379** | 646倍 |
| 3000・末尾 | 784,885 | 18,425 | **599〜361** | 1,300〜2,190倍 |
| 3000・外れ | 709,614 | 16,376 | **208〜340** | 2,700〜3,400倍 |
| 10・先頭 | 480 | 261 | 318 | 1.5倍(線形のほうが速いので8個以下は線形) |

走査コストがルート数に依存しなくなった(約200〜600ns一定)。なお測定の揺れは±数十%ある(同じ構成を繰り返すと値が変わる)。

## StarletteのRouter / FastAPIへの差し込み `mfastapi.accelerate(app)`(2026-11-14)
```python
import mfastapi
app = FastAPI(...)   # または Starlette(...) / Router(...)
mfastapi.accelerate(app)   # ルート登録の後に呼ぶ。要 Python 3 + mfastapi_native
```
**設計(安全第一)**: ルート探索の「候補の絞り込み」だけを置き換え、判定は本家に任せる。①パスで`RouteTable.first_match_from`を引き、パスが合う候補ルートを番号順に得る。②候補に本家の`route.matches(scope)`を呼ぶ(405のPARTIAL・`child_scope`・`path_params`の変換は本家のまま)。③最初のFULLを本家と同じ手順で処理(Starlette素の`Router.app`の分岐/FastAPIの`APIRouter.app`の分岐を再現)。④**FULLが無い場合は元の`Router.app`にそのまま委ねる**(405・redirect_slashes・FastAPIの低優先度・404の例外経路の挙動は一切変えない)。例外: プレーンなStarletteで「候補が1つも無く、redirect_slashesの候補も無い」場合だけ、全ルート走査を省いて直接`default`(404)へ進む。テンプレートを持たないルート(Host・独自BaseRoute・FastAPIの`include_router`由来など)は「全パス一致の候補」として表に入れ、本家の`matches`で最終判定する(絞り込みが緩いだけで結果は変わらない)。ルート数が8未満なら何もしない。ルート数や末尾が変わると表を作り直す(途中への挿入・並べ替えで数と末尾が同じ場合は`router._mfastapi_state`を消す必要がある)。

**等価性テスト**(`tests/accel/test_router_equiv.py`): Starlette・FastAPI(`include_router`のprefix・Mount・型付きパラメータ・405・末尾スラッシュ・redirect_slashes・日本語パス・多数のメソッド)の各315リクエストで、`accelerate`の有無を比較(ステータス・`Location`・`Allow`・本文)。Python 3.12・3.14で**不一致0**。FastAPIで実際に加速されていること、`accelerate`後に追加したルートが効くことも確認。

**性能**(`bench/bench_router.py`、何もしないASGIエンドポイントでRouter呼び出し全体を測定、ns/回、Python 3.12・WSL、Starlette 1.8.0):

| ルート数 | 当たる位置 | Starlette | accelerate | 倍率 |
|---|---|---|---|---|
| 10 | 先頭 | 3,843 | 4,954 | **0.8倍(遅い)** |
| 10 | 末尾 | 10,599 | 5,212 | 2.0倍 |
| 50 | 末尾 | 40,178 | 6,127 | 6.6倍 |
| 200 | 末尾 | 141,799 | 7,365 | 19.3倍 |
| 1000 | 末尾 | 662,984 | 8,508 | 77.9倍 |
| 200 | 404(外れ) | 261,517 | 8,531 | 30.7倍 |
| 1000 | 404(外れ) | 1,322,578 | 9,555 | 138倍 |

**正直な注意**: ①先頭のルートに当たる場合は本家が正規表現1回で済むため、一定の追加費用(約1µs)の分だけ**遅くなる**(10ルートで0.8倍)。損益分岐はおよそ3番目のルート。ルートが均等に使われるなら10ルートでも平均で得になるが、特定の先頭ルートに偏る場合は損。②速度はStarletteの素の`Router`で測った(FastAPIの実測は下の節)。③FastAPIの内部ヘルパ`fastapi.routing._route_selected`(非公開)に依存する(FastAPI 0.143.3で確認、無ければ本家へ委ねる)。④Starlette 1.8.0 / FastAPI 0.143.3 のみで検証。⑤`Router(middleware=...)`を使っている場合は警告して加速しない。⑥WebSocketは専用の等価性テストを追加した(下記)。

### 未完了だった項目の仕上げ(2026-11-14)
- **C版コンパイル済みルート表**(`c/mfastapi_cabi.c`の`mfastapi_table_*`、ctypesラッパー`mfastapi.native.CTable`): Mojo拡張が使えない環境(Windows等)でも`accelerate`が動くよう、`mfastapi_native`が無ければ自動でこれに切り替える。テンプレートを1回だけ保持し、**先頭リテラルのバイトtrie**で候補を絞ってからStarlette互換の照合をする(Mojo版と同じ考え方。同じ節のルートは番号順に連結し、最小番号の一致を返す)。`match`(path_params取得)は未提供。当初は線形走査だった(3000ルートの外れで7.4µs)が、trie化で**ルート数によらずほぼ一定**になった(`bench/bench_ctable.py`、ns/回、Python 3.12・WSL、ctypes呼び出しの約1.4µsを含む): 1000ルート末尾 1.6µs(Starletteの166倍)、3000ルート末尾 1.7µs(475倍)、3000ルート外れ 1.4µs(547倍)。先頭ルートに当たる場合は0.7〜0.8倍(ctypesの固定費のため遅い)。ライブラリの読み込みに失敗する例外はすべて本家へ委ねる。
- **C版の差分検証**(`bench/diff_ctable.py`): `first_match`と`first_match_from`をStarletteの`compile_path`と突き合わせ、**16万件×(Linux gcc・Python 3.12/3.14)で不一致0**、**4万件×(Windows MSVC x64・Python 3.13)で不一致0**。
- **CPython C拡張 `mfastapi_cext`**(`c/mfastapi_pyext.c`、`setup_cext.py`、Python 3専用): 同じC版ルート表をctypesを介さず呼ぶ。`accelerate`の優先順位は Mojo拡張 → `mfastapi_cext` → ctypes版。ctypesの固定費(約1.4µs)が消え、**先頭ルートに当たる場合でもStarletteの約4倍速い**(0.8倍→3.7〜4.5倍)。`first_match`は10〜3000ルートで0.18〜0.40µs(ルート数によらずほぼ一定、3000ルート外れでStarletteの約4,000倍(Linux)〜8,000倍(Windows))。Starlette差分(Linux Python 3.12/3.14で各16万件・Windows MSVC x64 Python 3.13で4万件)・等価性315件×2・WebSocket 7パスとも不一致0。Pythonのバージョンごとにビルドが必要(`scripts/test-cext-wsl.sh`・`scripts/build-windows.ps1`)。未配布(ホイール化・PyPI公開は未着手)。**ルーター全体(`bench_router.py`・`bench_router_fastapi.py`)をcext経由で測り直した結果(Linux・Python 3.12)は、Mojo拡張経由とほぼ同じ**: Starlette素のRouterは10ルート先頭0.8倍・末尾2.1倍、200ルート末尾19倍、1000ルート末尾88倍・外れ155倍。FastAPIは1000ルート末尾3.7倍、200ルート末尾1.6倍、先頭・外れは約1.0倍。つまりルーター全体では、照合そのもの(0.2〜0.4µs)ではなくPython側の差し込み処理(約4µs)が残りを占めており、表の高速化(Mojo→cext→trie)はこれ以上は全体に効かない。10ルート先頭が0.8倍(約0.8µs遅い)なのは、この差し込み処理の固定費のため。削るならPython側の処理(コルーチンの二重化・scopeの辞書参照)が対象で、未着手。
- **等価性テスト**はC版でも合格: Linux(Python 3.12/3.14)・Windows(MSVC x64・Python 3.13)とも、Starlette・FastAPI 各315リクエストで不一致0。
- **WebSocket**: 既存/未登録パス・パスパラメータ付き・余計な末尾など7パスで、Starlette・FastAPIともに`accelerate`の有無で接続結果が一致(Mojo版・C版の両方)。実際に接続できる経路が含まれていることも確認。
- **FastAPIの速度**(`bench/bench_router_fastapi.py`、何もしない軽いルートN本、ASGI呼び出し全体、Python 3.12・WSL・C版): 1リクエストが約0.42〜0.5ms(FastAPIの依存解決・応答生成が支配的)なので、効果は**ルートが多く、かつ末尾に近いものに当たる場合に限られる**。1000ルート末尾で3.5倍(1.74ms→0.50ms)、200ルート末尾で1.5倍。それ以外(先頭・50ルート以下)は1.0倍前後で差なし。**404(外れ)は加速されない**(1000ルートで2.25ms→2.25ms): FastAPIは`include_router`等で全パス一致の候補が混じるため近道を使わず本家に委ねる設計のため。
- 限界: Windowsで検証したのはC版(MSVC x64、Python 3.13)のみ。**ネイティブWindowsのMojo拡張・macOS・Android・iOSは、実行環境が無い/Mojoが未対応のため未検証**(macOSはMojo公式対応だがこのPCに実機なし)。
