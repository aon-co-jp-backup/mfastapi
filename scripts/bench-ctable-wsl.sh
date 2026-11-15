#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
bash /mnt/f/MFastAPI/scripts/cc-check-wsl.sh
export MFASTAPI_LIB="$HOME/mfastapi-c/libmfastapi_c.so" PYTHONPATH="/mnt/f/MFastAPI/python"
uv run --no-project --python 3.12 --with starlette --with fastapi python /mnt/f/MFastAPI/bench/bench_ctable.py
