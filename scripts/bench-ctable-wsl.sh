#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
bash /mnt/f/FastAPIM/scripts/cc-check-wsl.sh
export FASTAPIM_LIB="$HOME/fastapim-c/libfastapim_c.so" PYTHONPATH="/mnt/f/FastAPIM/python"
uv run --no-project --python 3.12 --with starlette --with fastapi python /mnt/f/FastAPIM/bench/bench_ctable.py
