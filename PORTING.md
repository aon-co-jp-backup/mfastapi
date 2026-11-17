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
