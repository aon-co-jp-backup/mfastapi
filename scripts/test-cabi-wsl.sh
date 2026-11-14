#!/usr/bin/env bash
# Mojo共有ライブラリをビルドし、Python 2.7(~/py27)と3.x(3.9/3.12/3.14)から呼んで確認する。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/test-cabi-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
. "$HOME/mfastapi-mojo/.venv/bin/activate"
mkdir -p "$HOME/mfastapi-mojo/build"
mojo build /mnt/f/mfastapi/mojo/mfastapi_cabi.mojo --emit shared-lib -o "$HOME/mfastapi-mojo/build/libmfastapi.so"
export MFASTAPI_LIB="$HOME/mfastapi-mojo/build/libmfastapi.so"
T=/mnt/f/mfastapi/tests/mojo/test_cabi.py
[ -x "$HOME/py27/bin/python2.7" ] && "$HOME/py27/bin/python2.7" "$T" || echo "python2.7 skipped (scripts/build-py27-wsl.sh)"
for v in 3.9 3.12 3.14; do uv run --no-project --python "$v" python "$T"; done
