#!/usr/bin/env bash
# 段階B(workers 1/2/4)と段階Cの並行負荷試験。クラッシュ・誤応答・スループットを見る。
#   wsl -d Ubuntu -- bash /mnt/f/FastAPIM/scripts/load-test-wsl.sh
set -uo pipefail
export PATH="$HOME/.pixi/bin:$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/FastAPIM
cd "$HOME/flare"
pixi run mojo build -I . -I $R/mojo $R/mojo/server_b.mojo -o "$HOME/fastapim-flare/server_b" 2>&1 | grep -i error
uv python install 3.12 >/dev/null 2>&1
PY=$(uv python find 3.12)
export MOJO_PYTHON_LIBRARY=$(find "$(dirname "$PY")/.." -name 'libpython3.12.so*' 2>/dev/null | head -1)
run() { # name url-path expect cmd...
  name=$1; path=$2; shift 2
  "$@" >/tmp/lt.log 2>&1 & pid=$!
  for i in $(seq 1 30); do curl -s -o /dev/null http://127.0.0.1:8821/health && break; sleep 1; done
  uv run --no-project --python 3.12 python $R/scripts/load_client.py http://127.0.0.1:8821 "$path" "$name"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; sleep 1
}
for w in 1 2 4; do run "B workers=$w /py/hello" /py/hello/Taro "$HOME/fastapim-flare/server_b" 8821 $R/examples $w; done
for w in 1 2 4; do run "B workers=$w /py/fib/20" /py/fib/20 "$HOME/fastapim-flare/server_b" 8821 $R/examples $w; done
run "C workers=2 /fib/30" /fib/30 "$HOME/fastapim-flare/server_c" 8821
