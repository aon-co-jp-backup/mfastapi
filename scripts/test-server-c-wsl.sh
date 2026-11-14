#!/usr/bin/env bash
# 段階C: 純Mojoサーバー(flare)を起動し、FastAPI(純Python版・Mojo関数版)と同じ要求で応答と速度を比べる。
#   前提: setup-flare-wsl.sh, build-server-c-wsl.sh, build-handlers-wsl.sh
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/test-server-c-wsl.sh
set -uo pipefail
export PATH="$HOME/.pixi/bin:$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/mfastapi
"$HOME/mfastapi-flare/server_c" 8801 >/tmp/server_c.log 2>&1 &
cpid=$!
PYTHONPATH="$HOME/mfastapi-mojo/build:$R/python:$R/tests/mojo_endpoint" uv run --no-project --python 3.12 --with fastapi --with uvicorn \
  uvicorn --app-dir $R/examples server_ab:app --port 8802 --log-level warning >/tmp/server_ab.log 2>&1 &
fpid=$!
for i in $(seq 1 60); do curl -s -o /dev/null http://127.0.0.1:8801/health && curl -s -o /dev/null http://127.0.0.1:8802/health && break; sleep 1; done
echo "== 応答(C=純Mojo / F=FastAPI+Mojo関数) =="
for p in /fib/0 /fib/20 /fib/abc /fib/46 "/primes" "/primes?n=100" "/primes?n=x" "/words?text=hello%20big%20world" /nope; do
  c=$(curl -s -w ' [%{http_code}]' "http://127.0.0.1:8801$p"); f=$(curl -s -w ' [%{http_code}]' "http://127.0.0.1:8802/mojo$p")
  echo "$p"; echo "    C: $c"; echo "    F: $f"
done
echo "== 速度(逐次リクエスト、1件あたりのus、keep-alive) =="
python3 - <<'PY'
import http.client, time
def run(port, path, n):
    c = http.client.HTTPConnection("127.0.0.1", port)
    c.request("GET", path); c.getresponse().read()
    t = time.perf_counter()
    for _ in range(n):
        c.request("GET", path); c.getresponse().read()
    return (time.perf_counter() - t) / n * 1e6
print("%-22s %12s %12s" % ("path", "pure Mojo us", "FastAPI+Mojo us"))
for label, p, n in (("/health", "/health", 3000), ("/fib/10", "/fib/10", 3000), ("/fib/30", "/fib/30", 20), ("/primes?n=1000000", "/primes?n=1000000", 20)):
    print("%-22s %12.0f %12.0f" % (label, run(8801, p, n), run(8802, "/mojo" + p, n)))
PY
kill $cpid $fpid 2>/dev/null; wait 2>/dev/null
