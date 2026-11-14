#!/usr/bin/env bash
# CPython C拡張(fastapim_cext)をビルドし、Starlette差分・等価性・速度を確認する(Python 3.12 / 3.14)。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/test-cext-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
for v in 3.12 3.14; do
  out="$HOME/mfastapi-cext/py$v"; mkdir -p "$out"
  (cd /mnt/f/mfastapi && uv run --no-project --python "$v" --with setuptools python setup_cext.py -q build_ext --build-lib "$out" --build-temp "$HOME/mfastapi-cext/tmp$v")
  export PYTHONPATH="$out:/mnt/f/mfastapi/python"
  unset FASTAPIM_LIB || true
  echo "[cext differential, Python $v]"
  uv run --no-project --python "$v" --with starlette --with fastapi python /mnt/f/mfastapi/bench/diff_cext.py 20000
  echo "[router equivalence via cext, Python $v]"
  uv run --no-project --python "$v" --with starlette --with fastapi --with httpx python /mnt/f/mfastapi/tests/accel/test_router_equiv.py
done
echo "[bench cext]"
export PYTHONPATH="$HOME/mfastapi-cext/py3.12:/mnt/f/mfastapi/python"
uv run --no-project --python 3.12 --with starlette --with fastapi python /mnt/f/mfastapi/bench/bench_ctable.py
