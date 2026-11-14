# -*- coding: utf-8 -*-
"""段階B: Mojo(flare)のサーバーから呼ばれる、利用者のPythonハンドラ。
Mojo側がHTTPとルーティングを担当し、ここの関数は「境界」を越えて呼ばれる(GILあり、引数・戻り値は文字列/数値)。"""


def greet(name):
    return '{"hello":"%s"}' % name


def _fib(n):
    return n if n < 2 else _fib(n - 1) + _fib(n - 2)


def fib(n):
    return str(_fib(int(n)))


def stats(csv):
    xs = [float(x) for x in csv.split(",") if x]
    return '{"n":%d,"mean":%r}' % (len(xs), sum(xs) / len(xs) if xs else 0.0)
