#!/usr/bin/env bash
# Mojo拡張(Python 3専用)をビルドし、Starletteとの差分検証と性能比較を行う。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/FastAPIM/scripts/test-ext-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
bash /mnt/f/FastAPIM/scripts/build-ext-wsl.sh
B="$HOME/fastapim-mojo/build"
. "$HOME/fastapim-mojo/.venv/bin/activate"
mojo build -I /mnt/f/FastAPIM/mojo /mnt/f/FastAPIM/mojo/fastapim_cabi.mojo --emit shared-lib -o "$B/libfastapim.so"
deactivate
export PYTHONPATH="$B" FASTAPIM_LIB="$B/libfastapim.so"
for v in 3.12 3.14; do
  echo "[differential, Python $v]"
  uv run --no-project --python "$v" --with starlette python /mnt/f/FastAPIM/bench/diff_table.py 20000
done
echo "[bench]"
uv run --no-project --python 3.12 --with starlette python /mnt/f/FastAPIM/bench/bench_match.py
echo "[bench params]"
uv run --no-project --python 3.12 --with starlette python /mnt/f/FastAPIM/bench/bench_params.py
