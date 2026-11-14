# -*- coding: utf-8 -*-
"""ネイティブ拡張はどちらも任意(optional)。Rust拡張 fastapim_rust(既定)とC拡張 fastapim_cext。
ビルドできない環境では拡張なしで入り、accelerateは本家のままで動く。"""
from setuptools import Extension, setup

try:
    from setuptools_rust import Binding, RustExtension

    rust = [RustExtension("fastapim_rust", path="rust/fastapim-py/Cargo.toml", binding=Binding.PyO3, optional=True)]
except ImportError:  # setuptools-rust が無い(Rustを使わない)環境
    rust = []

setup(
    ext_modules=[Extension("fastapim_cext", ["c/fastapim_pyext.c"], include_dirs=["c"], optional=True)],
    rust_extensions=rust,
)
