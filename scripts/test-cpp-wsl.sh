#!/usr/bin/env bash
# C++ speed core: build cpp/fastapim_cabi.cpp, diff against Starlette, bench vs the C table.
#   wsl -d Ubuntu -- bash /mnt/f/FastAPIM/scripts/test-cpp-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
R=/mnt/f/FastAPIM
mkdir -p "$HOME/fastapim-cpp"
g++ -std=c++17 -O3 -Wall -Wextra -shared -fPIC $R/cpp/fastapim_cabi.cpp -o "$HOME/fastapim-cpp/libfastapim_cpp.so"
gcc -O3 -shared -fPIC $R/c/fastapim_cabi.c -o "$HOME/fastapim-cpp/libfastapim_c.so"
nm -D "$HOME/fastapim-cpp/libfastapim_cpp.so" | grep -c " T fastapim_"
echo "[C++ vs Starlette]"
FASTAPIM_LIB="$HOME/fastapim-cpp/libfastapim_cpp.so" PYTHONPATH=$R/python uv run --no-project --python 3.12 --with starlette python $R/bench/diff_ctable.py 6000
echo "[bench C vs C++]"
for l in c cpp; do
  FASTAPIM_LIB="$HOME/fastapim-cpp/libfastapim_$l.so" PYTHONPATH=$R/python uv run --no-project --python 3.12 --with starlette python $R/bench/bench_ctable.py 2>&1 | tail -4
done
