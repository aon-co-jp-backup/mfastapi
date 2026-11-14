#!/usr/bin/env bash
# 段階B(Mojo受け口+Pythonハンドラ)サーバーを起動し、FastAPIと同じ422形式・OpenAPIか確認する。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/FastAPIM/scripts/test-server-b-compat-wsl.sh
set -uo pipefail
export PATH="$HOME/.pixi/bin:$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/FastAPIM
cd "$HOME/flare"
pixi run mojo build -I . -I $R/mojo $R/mojo/server_b.mojo -o "$HOME/fastapim-flare/server_b" 2>&1 | grep -i "error"
uv python install 3.12 >/dev/null 2>&1
PY=$(uv python find 3.12)
export MOJO_PYTHON_LIBRARY=$(find "$(dirname "$PY")/.." -name 'libpython3.12.so*' 2>/dev/null | head -1)
"$HOME/fastapim-flare/server_b" 8811 $R/examples >/tmp/server_b.log 2>&1 &
pid=$!
for i in $(seq 1 30); do curl -s -o /dev/null http://127.0.0.1:8811/health && break; sleep 1; done
PYTHONPATH="$HOME/fastapim-mojo/build:$R/python" uv run --no-project --python 3.12 --with fastapi --with httpx --with uvicorn \
  python $R/tests/mojo_endpoint/test_mojo_server_compat.py http://127.0.0.1:8811 b 2>&1 | grep -v -i deprecat
rc=${PIPESTATUS[0]}
kill $pid 2>/dev/null; wait $pid 2>/dev/null
exit $rc
