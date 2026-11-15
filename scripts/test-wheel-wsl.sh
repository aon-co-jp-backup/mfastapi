#!/usr/bin/env bash
# sdist/wheelをビルドして新しいvenvに入れ、cext経由で accelerate が動くことを確認する。
set -euo pipefail
export PATH="$HOME/.local/bin:/usr/bin:/bin"
W="$HOME/mfastapi-wheel"; rm -rf "$W"; mkdir -p "$W"
cp -r /mnt/f/MFastAPI/pyproject.toml /mnt/f/MFastAPI/setup.py /mnt/f/MFastAPI/MANIFEST.in /mnt/f/MFastAPI/README.md /mnt/f/MFastAPI/c /mnt/f/MFastAPI/python "$W/"
cd "$W"
uv build --wheel --python 3.12 -o dist >/dev/null
ls dist
uv venv --python 3.12 v >/dev/null
uv pip install --python v/bin/python dist/*.whl httpx >/dev/null
cd /
"$W/v/bin/python" - <<'PY'
import mfastapi, mfastapi.accel as a
print("table impl:", a._ext.__name__ if hasattr(a._ext, "__name__") else a._ext)
from fastapi import FastAPI
app = FastAPI()
for i in range(10):
    app.add_api_route("/r%d/{x}" % i, lambda x: {"x": x}, methods=["GET"])
mfastapi.accelerate(app)
from fastapi.testclient import TestClient
r = TestClient(app).get("/r9/5")
print(r.status_code, r.json())
assert r.status_code == 200
PY
