#!/usr/bin/env bash
# Mojo Python拡張(mfastapi_native.so、Python 3専用)をビルドする。出力: ~/mfastapi-mojo/build/mfastapi_native.so
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/MFastAPI/scripts/build-ext-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
. "$HOME/mfastapi-mojo/.venv/bin/activate"
mkdir -p "$HOME/mfastapi-mojo/build"
mojo build -I /mnt/f/MFastAPI/mojo /mnt/f/MFastAPI/mojo/mfastapi_native.mojo --emit shared-lib \
  -o "$HOME/mfastapi-mojo/build/mfastapi_native.so"
echo built mfastapi_native.so
