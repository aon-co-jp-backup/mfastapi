#!/usr/bin/env bash
# 段階A+: Mojoハンドラ拡張をビルドして、FastAPIエンドポイントとしての等価性と速度を確認する。
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
bash /mnt/f/mfastapi/scripts/build-handlers-wsl.sh
export PYTHONPATH="$HOME/mfastapi-mojo/build:/mnt/f/mfastapi/python"
for v in 3.12 3.14; do
  echo "[mojo endpoint, Python $v]"
  uv run --no-project --python "$v" --with fastapi --with httpx python /mnt/f/mfastapi/tests/mojo_endpoint/test_endpoint.py 2>&1 | grep -v -i deprecat
done
echo "[bench handlers]"
uv run --no-project --python 3.12 --with fastapi --with httpx python /mnt/f/mfastapi/bench/bench_handlers.py 2>&1 | grep -v -i deprecat
