# -*- coding: utf-8 -*-
# Python 2.7 / 3.x のどちらでも実行できる(pytest不要): python test_cabi.py
from __future__ import print_function
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "python", "mfastapi"))
import native  # noqa: E402  (パッケージ全体はPython 3専用のため、nativeだけを直接読む)


def check():
    assert native.add(2, 3) == 5
    assert native.path_matches("/v1/items/{item_id}", "/v1/items/42")
    assert native.path_matches("/", "/")
    assert native.path_matches(u"/u/{x}", u"/u/あ")  # 日本語(unicode / str)
    assert not native.path_matches("/v1/items/{item_id}", "/v1/items/")
    assert not native.path_matches("/v1/items/{item_id}", "/v1/items/1/2")
    assert not native.path_matches("/a", "/b")
    assert not native.path_matches("/a/{x}", "/a")


def test_cabi():
    check()


if __name__ == "__main__":
    check()
    print("OK python %d.%d" % sys.version_info[:2])
