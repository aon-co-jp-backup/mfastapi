#!/usr/bin/env bash
# Rust route table (drop-in libfastapim): diff against Starlette (diff_ctable) and bench vs the C table.
#   wsl -d Ubuntu -- bash /mnt/f/FastAPIM/scripts/test-rust-table-wsl.sh
set -euo pipefail
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/FastAPIM
export CARGO_TARGET_DIR="$HOME/fastapim-rust-target"
(cd $R/rust/fastapim-core && cargo build --release -q)
mkdir -p "$HOME/fastapim-cpp"; gcc -O3 -shared -fPIC $R/c/fastapim_cabi.c -o "$HOME/fastapim-cpp/libfastapim_c.so"
RS="$CARGO_TARGET_DIR/release/libfastapim_core.so"
echo "[Rust table vs Starlette]"
FASTAPIM_LIB="$RS" PYTHONPATH=$R/python uv run --no-project --python 3.12 --with starlette python $R/bench/diff_ctable.py 6000
echo "[bench: C then Rust]"
for l in "$HOME/fastapim-cpp/libfastapim_c.so" "$RS"; do
  FASTAPIM_LIB="$l" PYTHONPATH=$R/python uv run --no-project --python 3.12 --with starlette python $R/bench/bench_ctable.py 2>&1 | tail -4
done
