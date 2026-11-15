#!/usr/bin/env bash
# C++ speed core: build cpp/mfastapi_cabi.cpp, diff against Starlette, bench vs the C table.
#   wsl -d Ubuntu -- bash /mnt/f/MFastAPI/scripts/test-cpp-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/MFastAPI
mkdir -p "$HOME/mfastapi-cpp"
g++ -std=c++17 -O3 -Wall -Wextra -shared -fPIC $R/cpp/mfastapi_cabi.cpp -o "$HOME/mfastapi-cpp/libmfastapi_cpp.so"
gcc -O3 -shared -fPIC $R/c/mfastapi_cabi.c -o "$HOME/mfastapi-cpp/libmfastapi_c.so"
nm -D "$HOME/mfastapi-cpp/libmfastapi_cpp.so" | grep -c " T mfastapi_"
echo "[C++ vs Starlette]"
MFASTAPI_LIB="$HOME/mfastapi-cpp/libmfastapi_cpp.so" PYTHONPATH=$R/python uv run --no-project --python 3.12 --with starlette python $R/bench/diff_ctable.py 6000
echo "[bench C vs C++]"
for l in c cpp; do
  MFASTAPI_LIB="$HOME/mfastapi-cpp/libmfastapi_$l.so" PYTHONPATH=$R/python uv run --no-project --python 3.12 --with starlette python $R/bench/bench_ctable.py 2>&1 | tail -4
done
