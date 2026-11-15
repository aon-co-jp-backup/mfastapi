#!/usr/bin/env bash
# Mojo??????????????????????????? tests/mojo ???????????#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/MFastAPI/scripts/build-mojo-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
. "$HOME/mfastapi-mojo/.venv/bin/activate"
SRC=/mnt/f/MFastAPI
OUT="$HOME/mfastapi-mojo/build"; mkdir -p "$OUT"
mojo build -I "$SRC/mojo" "$SRC/mojo/mfastapi_native.mojo" --emit shared-lib -o "$OUT/mfastapi_native.so"
uv pip install -q pytest
rm -f "$OUT/test_cabi.py"
cp "$SRC/tests/mojo/parity.py" "$SRC/tests/mojo/test_native.py" "$OUT/"
(cd "$OUT" && python -m pytest -q .)
# test_cabi.py is a standalone script that needs libmfastapi.so: run scripts/test-cabi-wsl.sh instead.
