# -*- coding: utf-8 -*-
"""C拡張 mfastapi_cext は任意(optional)。コンパイラが無い環境では拡張なしで入り、accelerateはctypes版/本家のままで動く。"""
from setuptools import Extension, setup

setup(ext_modules=[Extension("mfastapi_cext", ["c/mfastapi_pyext.c"], include_dirs=["c"], optional=True)])
