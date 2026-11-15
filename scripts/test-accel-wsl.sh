#!/usr/bin/env bash
# accelerate() の等価性テストとルーター性能測定(Python 3 + Mojo拡張)。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/MFastAPI/scripts/test-accel-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
bash /mnt/f/MFastAPI/scripts/build-ext-wsl.sh
B="$HOME/mfastapi-mojo/build"
export PYTHONPATH="$B:/mnt/f/MFastAPI/python"
for v in 3.12 3.14; do
  echo "[router equivalence, Python $v]"
  uv run --no-project --python "$v" --with starlette --with fastapi --with httpx python /mnt/f/MFastAPI/tests/accel/test_router_equiv.py
done
echo "[router bench]"
uv run --no-project --python 3.12 --with starlette --with fastapi --with httpx python /mnt/f/MFastAPI/bench/bench_router.py
