# -*- coding: utf-8 -*-
"""CPython拡張 fastapim_cext のビルド(Python 3、setuptools)。
  python setup_cext.py build_ext --build-lib <出力dir> --build-temp <作業dir>"""
from setuptools import Extension, setup

setup(
    name="fastapim-cext",
    version="0.0.0",
    ext_modules=[Extension("fastapim_cext", ["c/fastapim_pyext.c"], include_dirs=["c"])],
    script_args=None,
)
