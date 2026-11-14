# -*- coding: utf-8 -*-
"""Mojo製の共有ライブラリ(C ABI)をctypesで呼ぶ。Python 2.7 / 3.x のどちらでも動く。

このファイルはPython 2構文でも読めるよう、型ヒント・f文字列・`from __future__`以外の新構文を使わない。
ライブラリの場所: 環境変数 MFASTAPI_LIB、または 同ディレクトリの libmfastapi.so / .dylib / mfastapi.dll。
"""
from __future__ import absolute_import, print_function

import ctypes
import os
import sys

_ABI_VERSION = 1
_lib = None


def _candidates():
    env = os.environ.get("MFASTAPI_LIB")
    if env:
        yield env
    here = os.path.dirname(os.path.abspath(__file__))
    for name in ("libmfastapi.so", "libmfastapi.dylib", "mfastapi.dll"):
        yield os.path.join(here, name)


def load(path=None):
    """共有ライブラリを読み込む。見つからなければ OSError。"""
    global _lib
    errors = []
    for p in ([path] if path else _candidates()):
        try:
            lib = ctypes.CDLL(p)
        except OSError as e:
            errors.append("%s: %s" % (p, e))
            continue
        lib.mfastapi_abi_version.restype = ctypes.c_int32
        lib.mfastapi_abi_version.argtypes = []
        if lib.mfastapi_abi_version() != _ABI_VERSION:
            raise OSError("ABI version mismatch in %s" % p)
        lib.mfastapi_add.restype = ctypes.c_int64
        lib.mfastapi_add.argtypes = [ctypes.c_int64, ctypes.c_int64]
        lib.mfastapi_path_matches.restype = ctypes.c_int32
        lib.mfastapi_path_matches.argtypes = [ctypes.c_char_p, ctypes.c_int64, ctypes.c_char_p, ctypes.c_int64]
        _lib = lib
        return lib
    raise OSError("mfastapi native library not found: " + "; ".join(errors))


def available():
    try:
        _get()
        return True
    except OSError:
        return False


def _get():
    return _lib if _lib is not None else load()


def _bytes(s):
    """str(py3)/unicode(py2)はUTF-8へ、bytes/str(py2)はそのまま。"""
    if isinstance(s, bytes):
        return s
    return s.encode("utf-8")


def add(a, b):
    return int(_get().mfastapi_add(a, b))


def path_matches(template, path):
    t, p = _bytes(template), _bytes(path)
    return bool(_get().mfastapi_path_matches(t, len(t), p, len(p)))
