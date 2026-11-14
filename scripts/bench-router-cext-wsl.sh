#!/usr/bin/env bash
# cext経由のRouter / FastAPI 全体の速度(test-cext-wsl.sh で先にビルド済みであること)。
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
export PYTHONPATH="$HOME/fastapim-cext/py3.12:/mnt/f/FastAPIM/python"
echo "[Starlette Router via cext]"
uv run --no-project --python 3.12 --with starlette --with fastapi python /mnt/f/FastAPIM/bench/bench_router.py
echo "[FastAPI via cext]"
uv run --no-project --python 3.12 --with starlette --with fastapi --with httpx python /mnt/f/FastAPIM/bench/bench_router_fastapi.py
