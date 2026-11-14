# -*- coding: utf-8 -*-
"""呼び出し1回あたりの固定費: ctypes(C ABI) と Mojo PythonModuleBuilder拡張 と 純Python。
使い方: MFASTAPI_LIB=<lib> PYTHONPATH=<mfastapi_native.soのdir> python bench/bench_overhead.py"""
import os, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "python", "mfastapi"))
import native

def best(fn, loops=200000, repeats=7):
    t = min((lambda s: (fn(loops), time.perf_counter() - s)[1])(time.perf_counter()) for _ in range(repeats))
    return t / loops * 1e9

def f_ctypes(n, add=native.add):
    for _ in range(n): add(2, 3)
def f_py(n):
    for _ in range(n): 2 + 3
print("add(2,3) ns/call: pure-python-op %.0f | ctypes-wrapper %.0f" % (best(f_py), best(f_ctypes)))
raw = native._get().mfastapi_add
def f_raw(n):
    for _ in range(n): raw(2, 3)
print("ctypes raw function pointer %.0f" % best(f_raw))
try:
    import mfastapi_native as m
    def f_ext(n, add=m.add):
        for _ in range(n): add(2, 3)
    print("Mojo PythonModuleBuilder ext %.0f" % best(f_ext))
except ImportError as e:
    print("Mojo ext not available:", e)
