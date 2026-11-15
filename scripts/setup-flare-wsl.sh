#!/usr/bin/env bash
# Flare(Mojo製のHTTPサーバー、MIT)をWSLに導入する(pixi経由)。段階B/C用。
#   PowerShell: wsl -d Ubuntu -- bash /mnt/f/MFastAPI/scripts/setup-flare-wsl.sh
set -euo pipefail
export PATH="$HOME/.pixi/bin:$HOME/.local/bin:/usr/bin:/bin"
command -v pixi >/dev/null || curl -fsSL https://pixi.sh/install.sh | bash
export PATH="$HOME/.pixi/bin:$PATH"
[ -d "$HOME/flare" ] || git clone --depth 1 https://github.com/ehsanmok/flare.git "$HOME/flare"
cd "$HOME/flare"
git log --oneline | head -3
ls
pixi install 2>&1 | tail -5
pixi run mojo --version
