#!/usr/bin/env bash
# Mojo Python拡張(fastapim_native.so、Python 3専用)をビルドする。出力: ~/fastapim-mojo/build/fastapim_native.so
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/FastAPIM/scripts/build-ext-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
. "$HOME/fastapim-mojo/.venv/bin/activate"
mkdir -p "$HOME/fastapim-mojo/build"
mojo build -I /mnt/f/FastAPIM/mojo /mnt/f/FastAPIM/mojo/fastapim_native.mojo --emit shared-lib \
  -o "$HOME/fastapim-mojo/build/fastapim_native.so"
echo built fastapim_native.so
