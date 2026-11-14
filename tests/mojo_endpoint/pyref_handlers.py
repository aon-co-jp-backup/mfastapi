# -*- coding: utf-8 -*-
"""Pure-Python equivalents of mojo/fastapim_handlers.mojo, used as the FastAPI reference when no Mojo build is available (CI)."""


def fib(n):
    if n < 0 or n > 45:
        raise ValueError("n must be between 0 and 45")
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a


def count_primes(n):
    if n < 0 or n > 100000000:
        raise ValueError("n must be between 0 and 100000000")
    if n < 2:
        return 0
    sieve = bytearray([1]) * (n + 1)
    sieve[0] = sieve[1] = 0
    i = 2
    while i * i <= n:
        if sieve[i]:
            sieve[i * i::i] = bytearray(len(range(i * i, n + 1, i)))
        i += 1
    return sum(sieve)


def word_count(text):
    return len([w for w in text.replace("\n", " ").replace("\t", " ").replace("\r", " ").split(" ") if w])


def mean(values):
    if not values:
        raise ValueError("mean of empty list")
    return sum(values) / len(values)
