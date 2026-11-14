#!/usr/bin/env bash
# C版(fastapim_cabi.c)を警告付きでコンパイルして共有ライブラリを作る。
set -euo pipefail
export PATH="/usr/bin:/bin"
mkdir -p "$HOME/fastapim-c"
gcc -std=c99 -O2 -Wall -Wextra -shared -fPIC -fvisibility=hidden /mnt/f/FastAPIM/c/fastapim_cabi.c -o "$HOME/fastapim-c/libfastapim_c.so"
echo "compiled OK: $HOME/fastapim-c/libfastapim_c.so"
