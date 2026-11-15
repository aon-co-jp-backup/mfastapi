#!/usr/bin/env bash
# Android: NDKのclangで4つのABI向けに libmfastapi.so をビルドする(Git Bash / WSL / Linux)。
#   ANDROID_NDK_HOME か、既定のWindows SDK位置のNDKを使う。出力: build/android/<abi>/libmfastapi.so
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NDK="${ANDROID_NDK_HOME:-$(ls -d "$LOCALAPPDATA"/Android/Sdk/ndk/* 2>/dev/null | tail -1)}"
BIN="$(ls -d "$NDK"/toolchains/llvm/prebuilt/*/bin | head -1)"
EXT=""; [ -f "$BIN/aarch64-linux-android24-clang.cmd" ] && EXT=".cmd"  # WindowsのNDKはclangのラッパーが.cmd
API=24
for pair in arm64-v8a:aarch64-linux-android armeabi-v7a:armv7a-linux-androideabi x86_64:x86_64-linux-android x86:i686-linux-android; do
  abi="${pair%%:*}"; tgt="${pair##*:}"
  mkdir -p "$ROOT/build/android/$abi"
  "$BIN/${tgt}${API}-clang${EXT}" -std=c99 -O2 -Wall -Wextra -shared -fPIC -fvisibility=hidden     "$ROOT/c/mfastapi_cabi.c" -o "$ROOT/build/android/$abi/libmfastapi.so"
  echo "built $abi"
done
