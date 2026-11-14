#!/usr/bin/env bash
# CPython C拡張(fastapim_cext)をビルドし、Starlette差分・等価性・速度を確認する(Python 3.12 / 3.14)。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/FastAPIM/scripts/test-cext-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
for v in 3.12 3.14; do
  out="$HOME/fastapim-cext/py$v"; mkdir -p "$out"
  (cd /mnt/f/FastAPIM && uv run --no-project --python "$v" --with setuptools python setup_cext.py -q build_ext --build-lib "$out" --build-temp "$HOME/fastapim-cext/tmp$v")
  export PYTHONPATH="$out:/mnt/f/FastAPIM/python"
  unset FASTAPIM_LIB || true
  echo "[cext differential, Python $v]"
  uv run --no-project --python "$v" --with starlette --with fastapi python /mnt/f/FastAPIM/bench/diff_cext.py 20000
  echo "[router equivalence via cext, Python $v]"
  uv run --no-project --python "$v" --with starlette --with fastapi --with httpx python /mnt/f/FastAPIM/tests/accel/test_router_equiv.py
done
echo "[bench cext]"
export PYTHONPATH="$HOME/fastapim-cext/py3.12:/mnt/f/FastAPIM/python"
uv run --no-project --python 3.12 --with starlette --with fastapi python /mnt/f/FastAPIM/bench/bench_ctable.py
