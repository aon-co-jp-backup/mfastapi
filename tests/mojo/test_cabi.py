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
    # Starlette互換: 型指定・区間内パラメータ・pathコンバータ
    assert native.path_matches("/n/{x:int}", "/n/42") and not native.path_matches("/n/{x:int}", "/n/4x")
    assert native.path_matches("/f/{x:float}", "/f/3.14") and not native.path_matches("/f/{x:float}", "/f/3.")
    assert native.path_matches("/files/{p:path}", "/files/a/b/c") and native.path_matches("/files/{p:path}", "/files/")
    assert native.path_matches("/v{x}.json", "/v12.json") and not native.path_matches("/v{x}.json", "/v.json")
    assert native.path_matches("/u/{i:uuid}", "/u/123e4567-e89b-12d3-a456-426614174000")
    assert native.path_matches("/{}", "/{}")  # 不正な波括弧はリテラル
    try:
        native.path_matches("/{x:nope}", "/a")
        raise AssertionError("expected ValueError")
    except ValueError:
        pass
    packed = native.pack_templates(["/", "/items/{id:int}", "/items/{name}", "/files/{p:path}"])
    assert native.route_first_match(packed, "/items/7") == 1
    assert native.route_first_match(packed, "/items/abc") == 2
    assert native.route_first_match(packed, "/files/x/y") == 3
    assert native.route_first_match(packed, "/nope/1") == -1


def test_cabi():
    check()


if __name__ == "__main__":
    check()
    print("OK python %d.%d" % sys.version_info[:2])
