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
    names = ("mfastapi.dll", "libmfastapi.dll", "mfastapi_core.dll") if os.name == "nt" else (
        ("libmfastapi.dylib", "libmfastapi.so", "libmfastapi_core.dylib") if sys.platform == "darwin" else ("libmfastapi.so", "libmfastapi_core.so")
    )
    for name in names:
        yield os.path.join(here, name)
    # Android(Chaquopy等のnativeLibraryDir)・iOS(アプリ同梱)はライブラリ名だけで探す。
    for name in names:
        yield name


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
        lib.mfastapi_route_first_match.restype = ctypes.c_int32
        lib.mfastapi_route_first_match.argtypes = [ctypes.c_char_p, ctypes.c_int64, ctypes.c_char_p, ctypes.c_int64]
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
    """Starlette互換のパス照合。未知の型名は ValueError、バックトラック上限は RuntimeError。"""
    t, p = _bytes(template), _bytes(path)
    r = _get().mfastapi_path_matches(t, len(t), p, len(p))
    if r == -1:
        raise ValueError("unknown path convertor in template: %r" % (template,))
    if r == -2:
        raise RuntimeError("path matching gave up (backtracking budget)")
    return r == 1


def pack_templates(templates):
    """route_first_matchへ渡す表(テンプレートを改行で連結)。ルート登録時に1回だけ作る。"""
    items = [_bytes(t) for t in templates]
    for t in items:
        if b"\n" in t:
            raise ValueError("template must not contain a newline")
    return b"\n".join(items)


def route_first_match(packed, path):
    """pack_templatesの結果に対し、最初に一致したテンプレートの番号を返す(なければ -1)。"""
    p = _bytes(path)
    r = _get().mfastapi_route_first_match(packed, len(packed), p, len(p))
    if r == -2:
        raise ValueError("unknown path convertor in a template")
    if r == -3:
        raise RuntimeError("path matching gave up (backtracking budget)")
    return r


class _CtypesTable(object):
    def __init__(self, templates):
        self._packed = pack_templates(templates)
        self._n = len(templates)

    def size(self):
        return self._n

    def first_match(self, path):
        return route_first_match(self._packed, path)


def table_available():
    """C版コンパイル済みルート表(mfastapi_table_*)を持つライブラリが読めるか(Mojo版ライブラリは持たない)。"""
    try:
        return hasattr(_get(), "mfastapi_table_new")
    except OSError:
        return False


class CTable(object):
    """C版のコンパイル済みルート表。テンプレートを1回だけ保持し、先頭リテラルで候補を落として照合する。
    first_match_from(path, start) は start 以降で最初に一致した番号(なければ -1)。"""

    def __init__(self, templates):
        lib = _get()
        if not hasattr(lib, "mfastapi_table_new"):
            raise OSError("this library has no compiled route table (build c/mfastapi_cabi.c)")
        lib.mfastapi_table_new.restype = ctypes.c_void_p
        lib.mfastapi_table_new.argtypes = []
        lib.mfastapi_table_free.restype = None
        lib.mfastapi_table_free.argtypes = [ctypes.c_void_p]
        lib.mfastapi_table_size.restype = ctypes.c_int32
        lib.mfastapi_table_size.argtypes = [ctypes.c_void_p]
        lib.mfastapi_table_add.restype = ctypes.c_int32
        lib.mfastapi_table_add.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int64]
        lib.mfastapi_table_first_match_from.restype = ctypes.c_int32
        lib.mfastapi_table_first_match_from.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int64, ctypes.c_int32]
        self._lib = lib
        self._h = lib.mfastapi_table_new()
        if not self._h:
            raise MemoryError("mfastapi_table_new failed")
        for t in templates:
            b = _bytes(t)
            r = lib.mfastapi_table_add(self._h, b, len(b))
            if r != 0:
                lib.mfastapi_table_free(self._h)
                self._h = None
                raise ValueError("template rejected (code %d): %r" % (r, t))

    def size(self):
        return int(self._lib.mfastapi_table_size(self._h))

    def first_match_from(self, path, start=0):
        p = _bytes(path)
        r = self._lib.mfastapi_table_first_match_from(self._h, p, len(p), start)
        if r == -3:
            raise RuntimeError("path matching gave up (backtracking budget)")
        return int(r)

    def first_match(self, path):
        return self.first_match_from(path, 0)

    def __del__(self):
        h = getattr(self, "_h", None)
        if h:
            try:
                self._lib.mfastapi_table_free(h)
            except Exception:
                pass
            self._h = None


def make_table(templates):
    """ルート表を作る。Python 3でMojo拡張(mfastapi_native)があればそれ(最速)、無ければctypes版。
    どちらも .first_match(path) -> 最初に一致したテンプレートの番号(なければ -1) を持つ。"""
    try:
        import mfastapi_native
        return mfastapi_native.RouteTable(list(templates))
    except ImportError:
        return _CtypesTable(list(templates))
