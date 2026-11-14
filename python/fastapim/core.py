# -*- coding: utf-8 -*-
"""Rust security core (rust/fastapim-core) through ctypes: Pydantic-lax int parsing and Starlette-compatible query lookup with hard limits.
Library: FASTAPIM_RS_LIB or libfastapim_core.so / .dylib / fastapim_core.dll next to this file."""
from __future__ import absolute_import
import ctypes
import os
import sys

_lib = None


def _load():
    global _lib
    if _lib is not None:
        return _lib
    here = os.path.dirname(os.path.abspath(__file__))
    names = ("fastapim_core.dll",) if os.name == "nt" else (("libfastapim_core.dylib",) if sys.platform == "darwin" else ("libfastapim_core.so",))
    cands = ([os.environ["FASTAPIM_RS_LIB"]] if os.environ.get("FASTAPIM_RS_LIB") else []) + [os.path.join(here, n) for n in names]
    for c in cands:
        try:
            lib = ctypes.CDLL(c)
        except OSError:
            continue
        lib.fastapim_rs_parse_int.restype = ctypes.c_int32
        lib.fastapim_rs_parse_int.argtypes = [ctypes.c_char_p, ctypes.c_int64, ctypes.POINTER(ctypes.c_int64)]
        lib.fastapim_rs_query_last.restype = ctypes.c_int64
        lib.fastapim_rs_query_last.argtypes = [ctypes.c_char_p, ctypes.c_int64, ctypes.c_char_p, ctypes.c_int64, ctypes.c_char_p, ctypes.c_int64]
        lib.fastapim_rs_query_last_len.restype = ctypes.c_int64
        lib.fastapim_rs_query_last_len.argtypes = [ctypes.c_char_p, ctypes.c_int64, ctypes.c_char_p, ctypes.c_int64]
        _lib = lib
        return lib
    raise OSError("fastapim Rust core not found (build rust/fastapim-core, set FASTAPIM_RS_LIB)")


def available():
    try:
        _load()
        return True
    except OSError:
        return False


def parse_int(s):
    """Return the int, or None when Pydantic would reject it. Raises OverflowError beyond int64, ValueError when over the length limit."""
    b = s.encode("utf-8") if not isinstance(s, bytes) else s
    out = ctypes.c_int64()
    r = _load().fastapim_rs_parse_int(b, len(b), ctypes.byref(out))
    if r == 0:
        return out.value
    if r == 1:
        return None
    if r == 2:
        raise OverflowError("integer out of int64 range")
    raise ValueError("input too long")


def query_last(query, name):
    """Last decoded value of `name` in a raw query string, or None if absent (duplicates: last wins; bare key: '')."""
    q = query.encode("utf-8") if not isinstance(query, bytes) else query
    k = name.encode("utf-8") if not isinstance(name, bytes) else name
    lib = _load()
    n = lib.fastapim_rs_query_last_len(q, len(q), k, len(k))
    if n == -1:
        return None
    if n < 0:
        raise ValueError("bad arguments")
    buf = ctypes.create_string_buffer(max(n, 1))
    r = lib.fastapim_rs_query_last(q, len(q), k, len(k), buf, n)
    if r < 0:
        raise ValueError("query_last failed (%d)" % r)
    return buf.raw[:r].decode("utf-8", "replace")
