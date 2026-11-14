#!/usr/bin/env bash
# 段階C: 純MojoのHTTPサーバー(flare上の型付きハンドラ)をビルドして起動確認する。要 setup-flare-wsl.sh。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/build-server-c-wsl.sh
set -uo pipefail
export PATH="$HOME/.pixi/bin:$HOME/.local/bin:/usr/bin:/bin"
cd "$HOME/flare"
mkdir -p "$HOME/mfastapi-flare"
pixi run mojo build -I . -I /mnt/f/mfastapi/mojo /mnt/f/mfastapi/mojo/server_c.mojo -o "$HOME/mfastapi-flare/server_c" 2>&1 | tail -30
ls -l "$HOME/mfastapi-flare/server_c"
