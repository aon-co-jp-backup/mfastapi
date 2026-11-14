# -*- coding: utf-8 -*-
"""本体は python/mfastapi_equiv_selftest.py(インストールされるモジュール)。ここは従来のパスで実行できるようにする薄いラッパー。"""
import runpy
import sys

sys.argv = sys.argv[:1]
runpy.run_module("mfastapi_equiv_selftest", run_name="__main__")
