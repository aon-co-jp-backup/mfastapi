# PORTING

## 2026-11-16 配布の仕上げ / Distribution finish
**日本語**: Windows 32bit wheel は配布済みと確認(古い「未了」を訂正)。Rust サーバー(`rust/mfastapi-server`)の単体バイナリを Linux/Windows/macOS の x64・ARM64 で CI ビルドし、起動して応答を確かめてから Release へ添付する(`.github/workflows/wheels.yml` の `server` ジョブ、v0.2.2〜)。**未了**: GET 以外のメソッド(サーバーは GET のみ・他は405)、Mojo 版サーバーの廃止判断、PyPI 公開(所有者のアカウントが必要)、Android/iOS/BSD/TV の実機。
**English**: Win32 wheels are confirmed shipped (the stale "not yet" was corrected). The standalone Rust server (`rust/mfastapi-server`) is CI-built for Linux/Windows/macOS on x64 and ARM64, smoke-tested (it starts and answers) and attached to the Release (`server` job in `.github/workflows/wheels.yml`, from v0.2.2). **Open**: non-GET methods (the server answers GET only, 405 otherwise), whether to retire the Mojo server, PyPI publication (needs the owner's account), real Android/iOS/BSD/TV devices.
