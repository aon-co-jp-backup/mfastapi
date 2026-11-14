#!/usr/bin/env bash
# 段階C(純Mojo)サーバーを起動し、FastAPIと同じ422形式・OpenAPIか確認する。要 setup-flare / build-server-c / build-handlers。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/test-server-compat-wsl.sh
set -uo pipefail
export PATH="$HOME/.pixi/bin:$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/mfastapi
"$HOME/mfastapi-flare/server_c" 8801 >/tmp/server_c.log 2>&1 &
pid=$!
for i in $(seq 1 30); do curl -s -o /dev/null http://127.0.0.1:8801/health && break; sleep 1; done
PYTHONPATH="$HOME/mfastapi-mojo/build:$R/python" uv run --no-project --python 3.12 --with fastapi --with httpx \
  python $R/tests/mojo_endpoint/test_mojo_server_compat.py http://127.0.0.1:8801 2>&1 | grep -v -i deprecat
rc=${PIPESTATUS[0]}
kill $pid 2>/dev/null; wait $pid 2>/dev/null
exit $rc
