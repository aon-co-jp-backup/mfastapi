# fastapim 設計書(新規設計・初版 2026-11-14)

Mojo Support for Python's FastAPI. 対象リポジトリ: https://github.com/aon-co-jp/FastAPIM (現状は空)。
この文書は調査結果に基づく設計案で、実装・コミット・fastapimリポジトリへの移動はまだ行っていない。

## 1. 調査結果(英語・日本語のWeb検索とGitHub検索)

| 対象 | 分かったこと | 設計への影響 |
|---|---|---|
| FastAPI 本家 | Starlette(ASGI)+Pydantic v2 の上に構築。型ヒントから検証・DI・OpenAPIを生成。版は検索結果で食い違う(0.141〜0.162付近)ため**着手時にPyPIで確認**。 | 互換の基準はFastAPIの公開API(デコレータ・`Depends`・`APIRouter`・OpenAPI出力)。 |
| Mojo→Python | `PythonModuleBuilder`で`.so`(拡張モジュール)化。`mojo build --emit shared-lib`、`mojo.importer`で自動ビルド。**ベータ**。キーワード専用引数・`**kwargs`・computed property未対応、stdlib外パッケージは手動ビルド。構文が版で変わる(`fn`→`def`、`python.bindings`→`std.python.bindings`)。 | Mojoを「Pythonから呼ぶ拡張」として使う層は薄く保ち、構文はMojo版を固定する。 |
| Python→Mojo呼び出し | Mojoから呼ぶPythonは`raises`必須、GILとインタプリタの費用でMojoの速さが消える。 | ホットパスにPython呼び出しを置かない設計にする。 |
| Lightbug(`Lightbug-HQ/lightbug_http`) | MIT、純Mojo HTTP/1.1。**2026-05-12にアーカイブ済み・本番不可**。 | 土台に採用しない。 |
| Flare(`ehsanmok/flare` v0.13.1、MIT) | HTTP/1.1・HTTP/2、WebSocket、TLS1.2/1.3(OpenSSL)、`SO_REUSEPORT`ワーカー、epoll/kqueue(io_uringは任意)、ルータ、ミドルウェア、gRPC・OpenAPI言及あり。2026-11-07更新、fuzz多数。 | **Mojo側HTTP土台の第一候補**。ただしMojo版・内部の循環importなど要確認。 |
| Milkha(PyPI) | Flare上の「FastAPI互換」Mojoフレームワーク。速度倍率(10〜50倍)は**公称の推定で実測ではない**。GitHubの元リポジトリはこの調査では見つからず(`ehsanmok/milkha`は404)。 | 競合/先行例。互換範囲を自前で定義し、倍率は自分で実測する。 |
| dodo(`dodo-mojo/dodo`、Apache-2.0) | Mojo製Webフレームワーク(AI/GPU/CV内蔵)、2026-11-11更新。 | 参考。思想が異なる(単独完結型)。 |
| Granian / Robyn | RustのHTTPサーバー(Hyper+Tokio、PyO3)がASGI/RSGI/WSGIのPythonアプリを動かす。 | **Rust層の先例**。FastAPI自体はそのまま載せて速くできる。 |

結論: 「FastAPI互換のMojoフレームワーク」は既にMilkhaが存在し、Lightbugは終了。
fastapimの価値は **(1)本家FastAPIアプリを壊さず段階的にMojo/Rustへ移せること、(2)RUNOの方針(Connect/gRPC・RS-JSON・共有基盤)に合うこと**に置く。

## 2. 目標と非目標

目標
- 本家FastAPIのコード(`@app.get`・`Depends`・Pydanticモデル)を**そのまま**動かし、重い所だけMojo/Rustへ差し替えられる。
- 純Mojoで書く道(Flare上の型付きハンドラ)も用意し、同じOpenAPIを出す。
- C++は**C ABI(`extern "C"`)経由の連携**(既存C++資産の呼び出し)に限定する。

非目標
- FastAPIの全機能の再実装(Pydanticの完全互換、全ミドルウェア等)。
- 新規RESTの拡張(CLAUDE.mdのREST全廃方針に従い、管理系APIはConnect/gRPC。FastAPI互換のHTTPは「互換のための入口」として提供し、新規の自前APIは方針どおりConnectで作る)。

## 3. アーキテクチャ(3段階、下に行くほど高速・低互換)

```
段階A  互換モード  : CPython FastAPI + Starlette
                     ├ サーバー: Rust (Granian相当/自前 fastapim-server, ASGI)
                     └ 計算: Mojo拡張(.so)/Rust拡張(PyO3)/C++(C ABI) を関数単位で差し替え
段階B  ハイブリッド: Mojoがルーティング・HTTP・検証を担当(Flare)、
                     Pythonハンドラは「境界」を越えて呼ぶ(GIL費用あり)
段階C  純Mojo      : Mojoの型付きハンドラのみ。Pythonは起動時の設定読み込み以外不使用。
```

共通の核(3段階で共有する契約):
1. **ルート表(IR)**: パス・メソッド・パラメータ型・応答型・依存関係をJSONで表す中間表現。FastAPIのデコレータ収集(段階A)とMojoの`comptime`宣言(段階C)の両方から生成。
2. **OpenAPI 3.1生成**: IRから出力。FastAPIの`/openapi.json`と差分比較するテストを置く(互換の客観指標)。
3. **検証**: Pydanticモデルは段階AでPydanticのまま。B/CではIRのスキーマからMojo側で検証。JSONは`RS-JSON`方針(サイズ・深さ・重複キー上限つき)で読む。

### 言語ごとの役割
- **Python**: 互換面(デコレータ、`Depends`、Pydantic)、利用者のコード。
- **Mojo**: 計算ホットパス(Pythonから`PythonModuleBuilder`で呼ぶ)、段階B/CのHTTP(Flare)。
- **Rust**: 前面サーバー・IR/OpenAPI生成・RS-JSON・PyO3拡張(Mojoのベータ機能に依存しない安定側)。
- **C++**: C ABI越しの既存ライブラリ呼び出しのみ。

### 配備方針との整合(CLAUDE.md 2026-11-09)
Mojoランタイム・計算基盤はVPSに**1回だけ**入れ、サイトごとに同梱しない。各サイトはfastapimをConnect/gRPCで呼ぶ。同時要求はワーカー/テナント単位で分離する。

## 4. 互換範囲(段階A→Cの順に広げる)

| 機能 | A | B | C |
|---|---|---|---|
| `@app.get/post/...`・パス/クエリ/本文 | ○ | ○ | ○ |
| Pydanticモデル検証 | ○(本家) | △(IR検証) | △ |
| `Depends`(DI) | ○ | △(同期/非同期の基本) | △ |
| `APIRouter`・ミドルウェア | ○ | △ | △ |
| OpenAPI 3.1・`/docs` | ○ | ○ | ○ |
| WebSocket・SSE | ○ | ○(Flare) | ○ |
| バックグラウンドタスク・lifespan | ○ | △ | 後回し |

○=対応、△=一部、空欄は未定。互換表は実装ごとにテスト結果で更新する(推測で○にしない)。

## 5. リポジトリ構成案(fastapim)

```
fastapim/
  README.md CLAUDE.md PORTING.md       # 日本語(GitHub側は後で多言語)
  python/fastapim/                     # 互換層・IR収集・importフック
  mojo/                                # PythonModuleBuilder拡張、段階B/C(Flare)
  rust/ (workspace)                    # server, ir, openapi, pyo3拡張
  cpp/                                 # C ABIラッパ(必要時のみ)
  tests/compat/                        # 本家FastAPIとの応答/OpenAPI差分テスト
  bench/                               # 実測(本家FastAPI・Granian・Milkhaと比較)
```

## 6. 検証計画(性能の主張は実測のみ)
1. 互換テスト: 本家FastAPI公式チュートリアルの例を段階A/B/Cで動かし、レスポンスと`/openapi.json`を差分比較。
2. 性能: plaintext/JSON/DB往復を、本家FastAPI(uvicorn)・Granian・Milkha・fastapim各段階で同一マシン・同一条件に測る。Milkhaの「10〜50倍」は鵜呑みにしない。
3. 境界費用: Mojo拡張を1リクエスト内で何回呼ぶとGIL費用が利得を上回るか測る。
4. セキュリティ: 外部入力はRS-JSONの上限つきパース、fuzz(Flare同様)をCIに。

## 7. 主なリスク
- Mojo→Python呼び出しは**ベータ**で構文が版ごとに変わる → Mojo版を固定、Rust(PyO3)を安定側の逃げ道に。
- Flareの単独メンテ依存・ライセンス/Mojo版の未確認 → 採用前に確認、代替はRust側サーバー(段階A)。
- Milkhaとの重複 → 差別化は「本家アプリの段階移行」と「RUNO方針整合」。
- FastAPIの版が速く動く → 互換基準版を固定し、追従は`version-control`で監視。

## 8. 次の一手(要判断)
1. 作業場所: `F:\mfastapi`にcloneして作るか(新規フォルダは事前相談の運用のため未作成)。
2. 段階Aの最小実装(IR収集+OpenAPI差分テスト)から着手するか。
3. FlareのMojo版・ライセンス・Mojoの実インストール可否(WSL等)の確認。

## 出典
- https://pypi.org/project/milkha/
- https://github.com/Lightbug-HQ/lightbug_http (2026-05-12アーカイブ)
- https://ehsanmok.github.io/flare/flare/
- https://mojolang.org/docs/manual/python/mojo-from-python/
- https://github.com/Aeron/granian
- https://github.com/dodo-mojo/dodo
- https://fastapi.tiangolo.com/release-notes/
