# Windows: MSVCで mfastapi.dll を x64 / x86 にビルドし、Python 3(64/32bit)で tests/mojo/test_cabi.py を実行する。
# PowerShellから: .\scripts\build-windows.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$vc = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
$out = Join-Path $root "build\windows"; New-Item -ItemType Directory -Force $out | Out-Null
foreach ($arch in @("x64", "x86")) {
    $dir = Join-Path $out $arch; New-Item -ItemType Directory -Force $dir | Out-Null
    $bat = Join-Path $dir "build.cmd"
    $lines = @("@echo off", "call `"$vc`" $arch >nul", "cd /d `"$dir`"", "cl /nologo /O2 /LD `"$root\c\mfastapi_cabi.c`" /Fe:mfastapi.dll")
    [System.IO.File]::WriteAllLines($bat, $lines, [System.Text.Encoding]::ASCII)
    cmd /c "`"$bat`" 2>nul"  # vcvarsallのvswhere警告(stderr)でStopしないよう捨てる。失敗は終了コードで判定
    if ($LASTEXITCODE -ne 0) { throw "build $arch failed" }
}
$py = @{ x64 = "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe"; x86 = "$env:LOCALAPPDATA\Programs\Python\Python314-32\python.exe" }
foreach ($arch in @("x64", "x86")) {
    $env:MFASTAPI_LIB = Join-Path $out "$arch\mfastapi.dll"
    & $py[$arch] (Join-Path $root "tests\mojo\test_cabi.py")
    if ($LASTEXITCODE -ne 0) { throw "test $arch failed" }
}
# C版ルート表(Mojo拡張なし)の Starlette 差分と accelerate 等価性。グローバルのPythonを汚さないよう build\venv に入れる。
$venv = Join-Path $root "build\venv"
if (-not (Test-Path "$venv\Scripts\python.exe")) {
    & $py["x64"] -m venv $venv
    & "$venv\Scripts\python.exe" -m pip install --quiet --disable-pip-version-check starlette fastapi httpx 2>$null
}
$env:MFASTAPI_LIB = Join-Path $out "x64\mfastapi.dll"
$env:PYTHONPATH = Join-Path $root "python"
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONWARNINGS = "ignore"
$ErrorActionPreference = "Continue"  # Pythonの警告(stderr)でStopしない。失敗は終了コードで判定
& "$venv\Scripts\python.exe" (Join-Path $root "bench\diff_ctable.py") 5000
if ($LASTEXITCODE -ne 0) { throw "ctable differential failed" }
& "$venv\Scripts\python.exe" (Join-Path $root "tests\accel\test_router_equiv.py")
if ($LASTEXITCODE -ne 0) { throw "router equivalence (C table) failed" }
