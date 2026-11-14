#!/usr/bin/env bash
# 検証専用: Python 2.7.18をソースから ~/py27 に入れる(Python 2はEOL。本番利用はしない)。
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin"
cd "$HOME/py27-src/Python-2.7.18"
make distclean >/dev/null 2>&1 || true
CFLAGS="-std=gnu11 -Wno-error" ./configure --prefix="$HOME/py27" > configure.log 2>&1
make -j8 > make.log 2>&1
make install > install.log 2>&1
"$HOME/py27/bin/python2.7" --version
