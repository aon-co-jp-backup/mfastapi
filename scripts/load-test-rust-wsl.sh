#!/usr/bin/env bash
# Rust server load test (16 parallel x 2000 requests): stage B (Python handlers) and C.
set -uo pipefail
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/MFastAPI
export CARGO_TARGET_DIR="$HOME/mfastapi-rust-target"
PY=$(uv python find 3.12); export LD_LIBRARY_PATH="$(dirname "$(dirname "$PY")")/lib:${LD_LIBRARY_PATH:-}"
BIN="$CARGO_TARGET_DIR/release/mfastapi-server"
run() { name=$1; path=$2; shift 2; "$BIN" "$@" >/tmp/rl.log 2>&1 & pid=$!
  for i in $(seq 1 30); do curl -s -o /dev/null http://127.0.0.1:8841/health && break; sleep 1; done
  uv run --no-project --python 3.12 python $R/scripts/load_client.py http://127.0.0.1:8841 "$path" "$name"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; }
run "Rust B /py/hello" /py/hello/Taro b 8841 $R/examples
run "Rust B /py/fib/20" /py/fib/20 b 8841 $R/examples
run "Rust C /fib/30" /fib/30 c 8841
run "Rust C /words" "/words?text=a%20b%20c" c 8841
