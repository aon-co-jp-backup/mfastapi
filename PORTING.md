# PORTING

## 2026-11-16 配布の仕上げ / Distribution finish
**日本語**: Windows 32bit wheel は配布済みと確認(古い「未了」を訂正)。Rust サーバー(`rust/mfastapi-server`)の単体バイナリを Linux/Windows/macOS の x64・ARM64 で CI ビルドし、起動して応答を確かめてから Release へ添付する(`.github/workflows/wheels.yml` の `server` ジョブ、v0.2.2〜)。**追記(2026-11-16)**: Rust サーバーが GET/HEAD/POST/PUT/PATCH/DELETE と JSON 本文に対応(`Route.method`/`Route.body`、`Args::json()`)。本文なしは422 `missing`、不正JSONは422 `json_invalid`、パスは合うがメソッド違いは405+`Allow`、本文1MB超は413、OpenAPI にメソッド別・`requestBody` を出力。CIのスモークにPOST/405/422を追加。 **決定(2026-11-16)**: 純Mojo版サーバー(ステージB/C)は廃止しない。通常の配布・機能追加はRust版(`rust/mfastapi-server`)を正とし、純Mojo版は「正しいMojoとして動くか」の確認テストが必要になったときに使う基準実装として残す(Mojo用CIも維持)。 **未了**: PyPI 公開(所有者のアカウントが必要)、Android/iOS/BSD/TV の実機。
**English**: Win32 wheels are confirmed shipped (the stale "not yet" was corrected). The standalone Rust server (`rust/mfastapi-server`) is CI-built for Linux/Windows/macOS on x64 and ARM64, smoke-tested (it starts and answers) and attached to the Release (`server` job in `.github/workflows/wheels.yml`, from v0.2.2). **Update (2026-11-16)**: the Rust server now handles GET/HEAD/POST/PUT/PATCH/DELETE and JSON bodies (`Route.method`/`Route.body`, `Args::json()`). A missing body gives 422 `missing`, invalid JSON 422 `json_invalid`, a path match with the wrong method 405 + `Allow`, bodies over 1 MB 413; OpenAPI lists per-method operations and `requestBody`. The CI smoke test now covers POST/405/422. **Decision (2026-11-16)**: the pure-Mojo server (stages B/C) is NOT retired. The Rust server (`rust/mfastapi-server`) is the primary one for distribution and new features; the pure-Mojo server stays as the reference implementation to use whenever a check as genuine Mojo is needed (the Mojo CI is kept). **Open**: PyPI publication (needs the owner's account), real Android/iOS/BSD/TV devices.

## 2026-11-17 到達点 / Status
**日本語**: v0.2.3 公開済み(win_arm64/win32を含むwheelとサーバーバイナリ)。未了: PyPI公開(所有者の認証が必要)、`rust/mfastapi-server/Cargo.lock`の未コミット差分。
**English**: v0.2.3 is released (wheels incl. win_arm64/win32 and server binaries). Open: PyPI (owner credentials), uncommitted `rust/mfastapi-server/Cargo.lock` diff.

## open-cpu の同梱と、アクセラレーターの扱い(2026-11-17)
- **同梱済み(実行時に AVX-512BW > AVX2 > NEON > スカラーを自動選択、`OPEN_CPU_MAX_ISA`で上限指定可)**: MFastAPI(`--cpu`、長いクエリ文字列の探索)、RMojo(`rmojo cpu`、`str.find`/`str.count`)、open-web-server・open-easy-web(起動時の要約、`System/GetCpu`、FastCGIヘッダー走査)。実機はNEONをSnapdragon端末2台で、AVX-512BWはCIで確認(開発PCはAVX2まで)。
- **2FastAPI**: 変換ツール(Python)で、実行時の計算処理を持たないため open-cpu は使わない。
- **open-cuda / aruaru-llm / open-directx は同梱しない**: 共有基盤を1回だけVPSに入れ、各サイトはConnect/gRPCで呼ぶ方針(本ファイル冒頭の配備アーキテクチャ方針)に従う。
- **ブラウザ(Windows/Linux/Mac/Android/iPhone)**: 計算はサーバー側で行うため、どの端末のブラウザからでも利用できる。RMojoのWASM(`wasm32-unknown-unknown`の`cargo check`は通過)は将来の遊び場候補。WASMでは open-cpu のSIMD自動選択は使わない。
- **スマホのアクセラレーター化**: `open-cpu/remote`(`open-cpu-remote`)。実測では手元PCが速いため自動判断は「手元のみ」で、手元が非力な場合に効く。詳細は`open-cpu/remote/README.md`。

## 起動時の自動バージョンアップ(2026-11-17)/ Self-update at startup
**日本語**: 起動のたびに前回の確認から24時間以上たっていれば、切り離した子プロセスで GitHub の最新リリースを調べ、新しければ取得して入れ替える(起動は遅くならない。更新は次回の起動から有効で、その旨を一度だけ表示)。**リリースの `<ファイル名>.sha256` と一致したときだけ**入れ替え、`.sha256` が無いリリース・GitHub 以外の取得先・先行版(-alpha 等)へは更新しない。信頼の根拠は GitHub への TLS と SHA-256(電子署名ではない)。手動実行と停止は下表。失敗は黙って次回に回し、理由は状態ディレクトリの `last_error` に残る。
**English**: On each start, if 24 h have passed since the last check, a detached child process queries the latest GitHub release and, if newer, downloads and swaps it in (startup is not delayed; the update takes effect on the next start, announced once). It installs **only if the SHA-256 matches the release's `<file>.sha256`**; releases without `.sha256`, non-GitHub hosts and pre-releases are refused. Trust = TLS to GitHub + SHA-256 (not a signature). Failures are silent and recorded in `last_error` in the state directory.
- MFastAPI: Python パッケージは `accelerate()` 呼び出し時に起動し、`pip download --no-index`(PyPI は見ない)で環境に合うホイールを取得→SHA-256 検証→`pip install --no-deps`。`mfastapi-server` バイナリは単体で自己入れ替え(Windows は実行中 exe を `.old` へ退避)。手動: `python -m mfastapi._autoupdate --now` / `mfastapi-server update`、停止: `MFASTAPI_NO_UPDATE=1`。状態: `~/.mfastapi/`。

## 上流の新版への追従(2026-11-17)/ Following upstream releases
- **定期試験**: CI を毎日(UTC 03:23)実行し、最新の Python・Flask・Django・FastAPI・Starlette(RMojo は最新の CPython との差分試験)で再試験。失敗したら日付つきの issue を1件起こす。
- **easy-web.tokyo**: `runo/scripts/refresh_versions.py` を VPS のタイマー(`easy-web-intros-refresh.timer`、1時間ごと)で実行し、MFastAPI・RMojo・2FastAPI・2FastAPI-VSC の最新版と上流(Python・Flask・Django・FastAPI・Starlette・Rust・Mojo)の最新版を各紹介ページと `/demo` に表示(`<製品>/versions.json`)。ページはダウンロード専用のまま。
- **未了**: 上流の新版が出たときに、利用者の環境(Flask/Django 等)まで自動で上げる機能は無い(本製品が更新するのは本製品自身)。aruaru-llm の同梱は未着手(open-cpu は同梱済み)。iPhone・iPad には対応していない。

## Android(aarch64)向けサーバーと自己更新(2026-11-17)/ Android server and self-update
**日本語**: v0.2.6 で `mfastapi-server-android-aarch64`(+`.sha256`)をReleaseへ添付。Android 14 実機(arm64)で、起動・`GET /fib/10`=55・`POST /echo`・`PUT`=405を確認し、版を0.0.1に偽装したビルドが `mfastapi-server update` で実リリース v0.2.6 を取得→SHA-256検証→置換→次回起動で通知まで通った。ビルドは `cargo ndk -t arm64-v8a`(`MSYS_NO_PATHCONV` をビルド時に設定しない。adb時だけ要る)。**未了**: PyPI公開(後回し)、iOS/BSD/TV実機。
**English**: v0.2.6 attaches `mfastapi-server-android-aarch64` (+`.sha256`). On a real Android 14 arm64 phone it starts, answers `GET /fib/10`=55, `POST /echo` and 405 for `PUT`; a build disguised as 0.0.1 ran `mfastapi-server update`, fetched the real v0.2.6, verified SHA-256, replaced itself and announced it on the next start. Build with `cargo ndk -t arm64-v8a` (do not set `MSYS_NO_PATHCONV` while building; only adb needs it). **Open**: PyPI publication (postponed), iOS/BSD/TV devices.
