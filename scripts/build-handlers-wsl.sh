#!/usr/bin/env bash
# Mojoハンドラ拡張(fastapim_handlers.so)をビルドする。出力: ~/fastapim-mojo/build/fastapim_handlers.so
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/FastAPIM/scripts/build-handlers-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
. "$HOME/fastapim-mojo/.venv/bin/activate"
mkdir -p "$HOME/fastapim-mojo/build"
mojo build -I /mnt/f/FastAPIM/mojo /mnt/f/FastAPIM/mojo/fastapim_handlers.mojo --emit shared-lib \
  -o "$HOME/fastapim-mojo/build/fastapim_handlers.so"
echo built fastapim_handlers.so
