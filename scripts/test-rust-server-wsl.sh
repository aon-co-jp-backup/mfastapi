#!/usr/bin/env bash
# Rust HTTP server layer: build, run stage C and B servers, compare with real FastAPI on uvicorn (same fuzz as the Mojo servers).
#   wsl -d Ubuntu -- bash /mnt/f/MFastAPI/scripts/test-rust-server-wsl.sh
set -uo pipefail
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/MFastAPI
export CARGO_TARGET_DIR="$HOME/mfastapi-rust-target"
uv python install 3.12 >/dev/null 2>&1
PY=$(uv python find 3.12)
export PYO3_PYTHON="$PY"
export LD_LIBRARY_PATH="$(dirname "$(dirname "$PY")")/lib:${LD_LIBRARY_PATH:-}"
cd $R/rust/mfastapi-server
cargo build --release --features python -q 2>&1 | grep -E "^(error|warning: unused)" -A6 | head -40
BIN="$CARGO_TARGET_DIR/release/mfastapi-server"
rc=0
run() { # mode port extra...
  "$BIN" "$@" >/tmp/rs.log 2>&1 & pid=$!
  for i in $(seq 1 30); do curl -s -o /dev/null http://127.0.0.1:$2/health && break; sleep 1; done
  PYTHONPATH="$HOME/mfastapi-mojo/build:$R/python" uv run --no-project --python 3.12 --with fastapi --with httpx --with uvicorn \
    python $R/tests/mojo_endpoint/test_mojo_server_compat.py http://127.0.0.1:$2 $1 2>&1 | grep -v -i "deprecat\|TestClient"
  r=${PIPESTATUS[0]}; [ $r -ne 0 ] && rc=$r
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
}
echo "== stage C (pure Rust)"; run c 8831
echo "== stage B (Rust HTTP + Python handlers)"; run b 8832 $R/examples
exit $rc
