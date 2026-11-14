#!/usr/bin/env bash
# Rust CPython extension (fastapim_rust): build, Starlette equivalence via accelerate, bench vs C ext.
#   wsl -d Ubuntu -- bash /mnt/f/FastAPIM/scripts/test-rust-ext-wsl.sh
set -euo pipefail
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/FastAPIM
export CARGO_TARGET_DIR="$HOME/fastapim-rust-target"
(cd $R/rust/fastapim-py && cargo build --release -q)
OUT="$HOME/fastapim-rust-ext"; mkdir -p "$OUT"
cp "$CARGO_TARGET_DIR/release/libfastapim_rust.so" "$OUT/fastapim_rust.so"
export PYTHONPATH="$OUT:$R/python"
for v in 3.12 3.14; do
  echo "[Python $v]"
  uv run --no-project --python $v --with starlette --with fastapi --with httpx python -c "import fastapim; print('backend =', fastapim.backend())"
  uv run --no-project --python $v --with starlette --with fastapi --with httpx python -m fastapim_equiv_selftest 2>&1 | tail -3
done
echo "[bench ctable: rust ext]"
uv run --no-project --python 3.12 --with starlette --with fastapi python $R/bench/bench_ctable.py 2>&1 | tail -4
