#!/usr/bin/env bash
# Mojo拡張(Python 3専用)をビルドし、Starletteとの差分検証と性能比較を行う。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/MFastAPI/scripts/test-ext-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
bash /mnt/f/MFastAPI/scripts/build-ext-wsl.sh
B="$HOME/mfastapi-mojo/build"
. "$HOME/mfastapi-mojo/.venv/bin/activate"
mojo build -I /mnt/f/MFastAPI/mojo /mnt/f/MFastAPI/mojo/mfastapi_cabi.mojo --emit shared-lib -o "$B/libmfastapi.so"
deactivate
export PYTHONPATH="$B" MFASTAPI_LIB="$B/libmfastapi.so"
for v in 3.12 3.14; do
  echo "[differential, Python $v]"
  uv run --no-project --python "$v" --with starlette python /mnt/f/MFastAPI/bench/diff_table.py 20000
done
echo "[bench]"
uv run --no-project --python 3.12 --with starlette python /mnt/f/MFastAPI/bench/bench_match.py
echo "[bench params]"
uv run --no-project --python 3.12 --with starlette python /mnt/f/MFastAPI/bench/bench_params.py
