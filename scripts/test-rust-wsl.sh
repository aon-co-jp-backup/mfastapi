#!/usr/bin/env bash
# Rust security core: cargo test + build cdylib + differential fuzz vs Pydantic / parse_qsl.
#   wsl -d Ubuntu -- bash /mnt/f/MFastAPI/scripts/test-rust-wsl.sh
set -euo pipefail
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/MFastAPI
cd $R/rust/mfastapi-core
export CARGO_TARGET_DIR="$HOME/mfastapi-rust-target"
cargo test --release -q 2>&1 | tail -3
cargo build --release -q
MFASTAPI_RS_LIB="$CARGO_TARGET_DIR/release/libmfastapi_core.so" PYTHONPATH=$R/python uv run --no-project --python 3.12 --with pydantic --with starlette python $R/tests/test_rust_core.py
