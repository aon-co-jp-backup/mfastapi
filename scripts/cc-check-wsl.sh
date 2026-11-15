#!/usr/bin/env bash
# C版(mfastapi_cabi.c)を警告付きでコンパイルして共有ライブラリを作る。
set -euo pipefail
export PATH="/usr/bin:/bin"
mkdir -p "$HOME/mfastapi-c"
gcc -std=c99 -O2 -Wall -Wextra -shared -fPIC -fvisibility=hidden /mnt/f/MFastAPI/c/mfastapi_cabi.c -o "$HOME/mfastapi-c/libmfastapi_c.so"
echo "compiled OK: $HOME/mfastapi-c/libmfastapi_c.so"
