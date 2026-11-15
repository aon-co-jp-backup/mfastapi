#!/usr/bin/env bash
# Mojoハンドラ拡張(mfastapi_handlers.so)をビルドする。出力: ~/mfastapi-mojo/build/mfastapi_handlers.so
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/MFastAPI/scripts/build-handlers-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
. "$HOME/mfastapi-mojo/.venv/bin/activate"
mkdir -p "$HOME/mfastapi-mojo/build"
mojo build -I /mnt/f/MFastAPI/mojo /mnt/f/MFastAPI/mojo/mfastapi_handlers.mojo --emit shared-lib \
  -o "$HOME/mfastapi-mojo/build/mfastapi_handlers.so"
echo built mfastapi_handlers.so
