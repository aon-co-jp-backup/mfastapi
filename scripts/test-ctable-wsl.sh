#!/usr/bin/env bash
# C版ルート表: Starlette差分、Mojo拡張なしでの accelerate 等価性テスト(Python 3.12 / 3.14)。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/MFastAPI/scripts/test-ctable-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
bash /mnt/f/MFastAPI/scripts/cc-check-wsl.sh
export MFASTAPI_LIB="$HOME/mfastapi-c/libmfastapi_c.so"
export PYTHONPATH="/mnt/f/MFastAPI/python"
for v in 3.12 3.14; do
  echo "[C table differential, Python $v]"
  uv run --no-project --python "$v" --with starlette --with fastapi python /mnt/f/MFastAPI/bench/diff_ctable.py 20000
  echo "[router equivalence via C table, Python $v]"
  uv run --no-project --python "$v" --with starlette --with fastapi --with httpx python /mnt/f/MFastAPI/tests/accel/test_router_equiv.py
done
echo "[FastAPI router bench via C table]"
uv run --no-project --python 3.12 --with starlette --with fastapi --with httpx python /mnt/f/MFastAPI/bench/bench_router_fastapi.py
