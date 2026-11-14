#!/usr/bin/env bash
# Starlette / FastAPI の複数バージョンで accelerate の等価性テストを実行する(cext経由、Python 3.12)。
#   使い方: wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/test-versions-wsl.sh   (先に test-cext-wsl.sh でcextをビルド)
set -uo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
export PYTHONPATH="$HOME/mfastapi-cext/py3.12:/mnt/f/mfastapi/python"
for combo in "starlette==0.46.2 fastapi==0.115.14" "starlette==0.52.1 fastapi==0.128.8" "starlette fastapi"; do
  set -- $combo
  echo "=== $combo ==="
  uv run --no-project --python 3.12 --with "$1" --with "$2" --with httpx python - <<'PY' 2>&1 | grep -v -i deprecat | tail -8
import starlette, fastapi
print("starlette", starlette.__version__, "fastapi", fastapi.__version__)
import runpy, sys
sys.argv = ["t"]
try:
    runpy.run_path("/mnt/f/mfastapi/tests/accel/test_router_equiv.py", run_name="__main__")
except SystemExit as e:
    print("exit", e.code)
PY
done
