# -*- coding: utf-8 -*-
"""ネイティブ拡張はどちらも任意(optional)。Rust拡張 mfastapi_rust(既定)とC拡張 mfastapi_cext。
ビルドできない環境では拡張なしで入り、accelerateは本家のままで動く。"""
from setuptools import Extension, setup

try:
    from setuptools_rust import Binding, RustExtension

    rust = [RustExtension("mfastapi_rust", path="rust/mfastapi-py/Cargo.toml", binding=Binding.PyO3, optional=True)]
except ImportError:  # setuptools-rust が無い(Rustを使わない)環境
    rust = []

setup(
    ext_modules=[Extension("mfastapi_cext", ["c/mfastapi_pyext.c"], include_dirs=["c"], optional=True)],
    rust_extensions=rust,
)
