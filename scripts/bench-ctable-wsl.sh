#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
bash /mnt/f/mfastapi/scripts/cc-check-wsl.sh
export FASTAPIM_LIB="$HOME/mfastapi-c/libfastapim_c.so" PYTHONPATH="/mnt/f/mfastapi/python"
uv run --no-project --python 3.12 --with starlette --with fastapi python /mnt/f/mfastapi/bench/bench_ctable.py
