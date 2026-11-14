#!/usr/bin/env bash
# Linux: C版をgccでビルド→テスト、Mojo版とのパリティ検証。Python 2.7 / 3.x で実行する。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/test-cross-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
B="$HOME/mfastapi-mojo/build"; mkdir -p "$B"
gcc -std=c99 -O2 -Wall -Wextra -shared -fPIC -fvisibility=hidden /mnt/f/mfastapi/c/mfastapi_cabi.c -o "$B/libmfastapi_c.so"
. "$HOME/mfastapi-mojo/.venv/bin/activate"
mojo build /mnt/f/mfastapi/mojo/mfastapi_cabi.mojo --emit shared-lib -o "$B/libmfastapi.so"
T=/mnt/f/mfastapi/tests/mojo
for lib in libmfastapi.so libmfastapi_c.so; do
  for py in "$HOME/py27/bin/python2.7" python; do
    echo "[$lib / $($py --version 2>&1)]"; MFASTAPI_LIB="$B/$lib" "$py" "$T/test_cabi.py"
  done
done
echo "[parity Mojo vs C, Python 3]"; python "$T/parity.py" "$B/libmfastapi.so" "$B/libmfastapi_c.so"
echo "[parity Mojo vs C, Python 2.7]"; "$HOME/py27/bin/python2.7" "$T/parity.py" "$B/libmfastapi.so" "$B/libmfastapi_c.so"
for lib in libmfastapi.so libmfastapi_c.so; do
  echo "[Starlette differential, $lib]"
  MFASTAPI_LIB="$B/$lib" uv run --no-project --python 3.12 --with starlette python /mnt/f/mfastapi/bench/diff_starlette.py 300000 | grep -E "cases|agree|e\.g|typed|param|other|invalid"
done
for lib in libmfastapi.so libmfastapi_c.so; do
  echo "[bench $lib]"
  MFASTAPI_LIB="$B/$lib" uv run --no-project --python 3.12 --with starlette python /mnt/f/mfastapi/bench/bench_match.py
done
