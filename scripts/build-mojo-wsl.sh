#!/usr/bin/env bash
# Mojo??????????????????????????? tests/mojo ???????????#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/FastAPIM/scripts/build-mojo-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
. "$HOME/fastapim-mojo/.venv/bin/activate"
SRC=/mnt/f/FastAPIM
OUT="$HOME/fastapim-mojo/build"; mkdir -p "$OUT"
mojo build -I "$SRC/mojo" "$SRC/mojo/fastapim_native.mojo" --emit shared-lib -o "$OUT/fastapim_native.so"
uv pip install -q pytest
cp "$SRC/tests/mojo/"*.py "$OUT/"
cd "$OUT" && python -m pytest -q .
