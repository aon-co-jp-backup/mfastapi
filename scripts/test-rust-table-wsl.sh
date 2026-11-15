#!/usr/bin/env bash
# Rust route table (drop-in libmfastapi): diff against Starlette (diff_ctable) and bench vs the C table.
#   wsl -d Ubuntu -- bash /mnt/f/MFastAPI/scripts/test-rust-table-wsl.sh
set -euo pipefail
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/MFastAPI
export CARGO_TARGET_DIR="$HOME/mfastapi-rust-target"
(cd $R/rust/mfastapi-core && cargo build --release -q)
mkdir -p "$HOME/mfastapi-cpp"; gcc -O3 -shared -fPIC $R/c/mfastapi_cabi.c -o "$HOME/mfastapi-cpp/libmfastapi_c.so"
RS="$CARGO_TARGET_DIR/release/libmfastapi_core.so"
echo "[Rust table vs Starlette]"
MFASTAPI_LIB="$RS" PYTHONPATH=$R/python uv run --no-project --python 3.12 --with starlette python $R/bench/diff_ctable.py 6000
echo "[bench: C then Rust]"
for l in "$HOME/mfastapi-cpp/libmfastapi_c.so" "$RS"; do
  MFASTAPI_LIB="$l" PYTHONPATH=$R/python uv run --no-project --python 3.12 --with starlette python $R/bench/bench_ctable.py 2>&1 | tail -4
done
