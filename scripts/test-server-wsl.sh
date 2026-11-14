#!/usr/bin/env bash
# 実際のLinux Webサーバー(uvicorn)で、3つのモード(Mojo拡張 / C拡張 / 拡張なし)が同じ応答を返し、動くことを確認する。
#   前提: test-cext-wsl.sh でC拡張を、build-ext-wsl.sh でMojo拡張をビルド済み
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/FastAPIM/scripts/test-server-wsl.sh
set -uo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/FastAPIM
declare -A PP=( [mojo]="$HOME/fastapim-mojo/build:$R/python" [cext]="$HOME/fastapim-cext/py3.12:$R/python" [none]="$R/python" )
PATHS="/svc0/items /api/v1/res1/abc /api/v1/res199/z /svc198/items /files/a/b/c /nope /svc0/items/ /__backend"
rm -rf /tmp/mf-srv; mkdir -p /tmp/mf-srv
port=8700
for mode in mojo cext none; do
  port=$((port+1))
  PYTHONPATH="${PP[$mode]}" uv run --no-project --python 3.12 --with starlette --with fastapi --with uvicorn \
    uvicorn --app-dir $R/examples server_app:app --port $port --log-level warning >/tmp/mf-srv/$mode.log 2>&1 &
  pid=$!
  for i in $(seq 1 60); do curl -s -o /dev/null http://127.0.0.1:$port/nope && break; sleep 1; done
  for p in $PATHS; do
    echo "$p $(curl -s -o /tmp/mf-srv/body -w '%{http_code}' http://127.0.0.1:$port$p) $(cat /tmp/mf-srv/body)"
  done > /tmp/mf-srv/$mode.out
  PYTHONPATH="${PP[$mode]}" uv run --no-project --python 3.12 --with httpx python - $port $mode <<'PY'
import sys, time, http.client
port, mode = int(sys.argv[1]), sys.argv[2]
c = http.client.HTTPConnection("127.0.0.1", port)
def run(path, n=3000):
    t = time.perf_counter()
    for _ in range(n):
        c.request("GET", path); c.getresponse().read()
    return (time.perf_counter() - t) / n * 1e6
print("%-5s req/last-route: %6.0f us   first-route: %6.0f us   404: %6.0f us" % (mode, run("/api/v1/res199/z"), run("/svc0/items"), run("/nope")))
PY
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  echo "[$mode] $(grep 'fastapim backend' /tmp/mf-srv/$mode.log | head -1)"
done
echo "== 応答の比較(/__backend 行は実装名が違うので除く) =="
for m in mojo cext; do
  if diff <(grep -v __backend /tmp/mf-srv/none.out) <(grep -v __backend /tmp/mf-srv/$m.out) >/dev/null; then echo "$m == none : 同一"; else echo "$m != none : 差あり"; diff /tmp/mf-srv/none.out /tmp/mf-srv/$m.out; fi
done
grep __backend /tmp/mf-srv/*.out
