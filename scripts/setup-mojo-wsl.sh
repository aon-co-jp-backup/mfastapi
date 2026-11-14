#!/usr/bin/env bash
# WSL(Ubuntu)へMojoを導入する。Windows側PATHの括弧で壊れないよう、必ずスクリプトファイル経由で実行する。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/mfastapi/scripts/setup-mojo-wsl.sh
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
mkdir -p "$HOME/mfastapi-mojo" && cd "$HOME/mfastapi-mojo"
[ -d .venv ] || uv venv --python 3.12 .venv
. .venv/bin/activate
uv pip install mojo --extra-index-url https://whl.modular.com/nightly/simple/ --prerelease allow
mojo --version
