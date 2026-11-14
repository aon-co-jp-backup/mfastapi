#!/usr/bin/env bash
# fastapi なし(Starletteのみ)でも import mfastapi / accelerate / 等価性テストが動くことを確認する(要 test-cext-wsl.sh でcextをビルド済み)。
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
export PYTHONPATH="$HOME/mfastapi-cext/py3.12:/mnt/f/mfastapi/python"
echo "[starlette only]"
uv run --no-project --python 3.12 --with starlette --with httpx python /mnt/f/mfastapi/tests/accel/test_router_equiv.py 2>&1 | grep -v -i deprecat | tail -6
echo "[with fastapi]"
uv run --no-project --python 3.12 --with starlette --with fastapi --with httpx python /mnt/f/mfastapi/tests/accel/test_router_equiv.py 2>&1 | grep -v -i deprecat | tail -6
