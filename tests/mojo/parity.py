# -*- coding: utf-8 -*-
"""2つのネイティブ実装(Mojo版・C版)が同じ答えを返すか、ランダム入力で突き合わせる(Python 2/3両対応)。
使い方: python parity.py <libA> <libB>"""
from __future__ import print_function
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "python", "mfastapi"))
import native  # noqa: E402


def lib_fn(path):
    lib = native.load(path)
    def f(t, p):
        return bool(lib.mfastapi_path_matches(t, len(t), p, len(p)))
    return f


def rnd(rng, alphabet, maxlen):
    return "".join(rng.choice(alphabet) for _ in range(rng.randint(0, maxlen))).encode("utf-8")


def main():
    a, b = lib_fn(sys.argv[1]), lib_fn(sys.argv[2])
    rng = random.Random(12345)
    n = 200000
    hits = 0
    for _ in range(n):
        t = rnd(rng, "ab{}/x", 10)
        # 半分はテンプレートから作ったパスで、一致するケースも十分に含める
        p = t.replace(b"{x}", b"v").replace(b"{}", b"w") if rng.random() < 0.5 else rnd(rng, "abv/xw", 10)
        ra, rb = a(t, p), b(t, p)
        if ra != rb:
            print("MISMATCH", t, p, ra, rb)
            sys.exit(1)
        hits += ra
    print("parity OK: %d cases, %d matched" % (n, hits))


if __name__ == "__main__":
    main()
