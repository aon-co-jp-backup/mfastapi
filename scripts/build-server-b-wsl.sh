#!/usr/bin/env bash
# 段階B: MojoのHTTPサーバー + Pythonハンドラ(境界越え)をビルドし、起動して確認する。要 setup-flare-wsl.sh。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/FastAPIM/scripts/build-server-b-wsl.sh
set -uo pipefail
export PATH="$HOME/.pixi/bin:$HOME/.local/bin:/usr/bin:/bin"
cd "$HOME/flare"
mkdir -p "$HOME/fastapim-flare"
pixi run mojo build -I . -I /mnt/f/FastAPIM/mojo /mnt/f/FastAPIM/mojo/server_b.mojo -o "$HOME/fastapim-flare/server_b" 2>&1 | tail -30
ls -l "$HOME/fastapim-flare/server_b" || exit 1
# 埋め込むPython(共有ライブラリ)を探す。uvのPython 3.12を使う。
uv python install 3.12 >/dev/null 2>&1
PY=$(uv python find 3.12)
LIB=$(find "$(dirname "$PY")/.." -name 'libpython3.12.so*' 2>/dev/null | head -1)
echo "python=$PY lib=$LIB"
export MOJO_PYTHON_LIBRARY="$LIB"
"$HOME/fastapim-flare/server_b" 8811 /mnt/f/FastAPIM/examples >/tmp/server_b.log 2>&1 &
pid=$!
for i in $(seq 1 30); do curl -s -o /dev/null http://127.0.0.1:8811/health && break; sleep 1; done
for p in /health /py/hello/Taro /py/fib/20 "/py/stats?csv=1,2,3.5" /fib/20 /py/fib/99 /nope; do echo "$p => $(curl -s -w ' [%{http_code}]' http://127.0.0.1:8811$p)"; done
python3 - <<'PY'
import http.client, time
def run(path, n):
    c = http.client.HTTPConnection("127.0.0.1", 8811)
    c.request("GET", path); c.getresponse().read()
    t = time.perf_counter()
    for _ in range(n):
        c.request("GET", path); c.getresponse().read()
    return (time.perf_counter() - t) / n * 1e6
print("%-16s %10s" % ("path", "us/request"))
for p, n in (("/health", 3000), ("/py/hello/Taro", 3000), ("/fib/10", 3000), ("/py/fib/10", 500), ("/fib/30", 20), ("/py/fib/30", 3)):
    print("%-16s %10.0f" % (p, run(p, n)))
PY
kill $pid 2>/dev/null; wait $pid 2>/dev/null
tail -3 /tmp/server_b.log
