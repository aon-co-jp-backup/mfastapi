"""Mojo handlers callable from Python/FastAPI (stage A+): compute-heavy endpoint bodies written in Mojo.

Build: mojo build mojo/fastapim_handlers.mojo --emit shared-lib -o build/fastapim_handlers.so
Use:   from fastapim import mojo_endpoint; app.add_api_route("/fib/{n}", mojo_endpoint(h.fib, {"n": int}, int))
"""
from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder
from std.os import abort


@export
def PyInit_fastapim_handlers() abi("C") -> PythonObject:
    try:
        var m = PythonModuleBuilder("fastapim_handlers")
        m.def_function[fib]("fib", docstring="fib(n): naive recursive Fibonacci (CPU-bound demo)")
        m.def_function[count_primes]("count_primes", docstring="count_primes(n): number of primes <= n (sieve)")
        m.def_function[word_count]("word_count", docstring="word_count(text): number of whitespace-separated words")
        m.def_function[mean]("mean", docstring="mean(list_of_numbers) -> float")
        return m.finalize()
    except e:
        abort(String("error creating fastapim_handlers:", e))


def fib_rec(n: Int) -> Int:
    if n < 2:
        return n
    return fib_rec(n - 1) + fib_rec(n - 2)


def fib(n: PythonObject) raises -> PythonObject:
    var k = Int(py=n)
    if k < 0 or k > 45:
        raise Error("n must be between 0 and 45")
    return PythonObject(fib_rec(k))


def count_primes(n: PythonObject) raises -> PythonObject:
    var limit = Int(py=n)
    if limit < 0 or limit > 100000000:
        raise Error("n must be between 0 and 100000000")
    if limit < 2:
        return PythonObject(0)
    var sieve = List[Bool](length=limit + 1, fill=True)
    sieve[0] = False
    sieve[1] = False
    var i = 2
    while i * i <= limit:
        if sieve[i]:
            var j = i * i
            while j <= limit:
                sieve[j] = False
                j += i
        i += 1
    var count = 0
    for k in range(limit + 1):
        if sieve[k]:
            count += 1
    return PythonObject(count)


def word_count(text: PythonObject) raises -> PythonObject:
    var s = String(py=text)
    var count = 0
    var in_word = False
    for b in s.as_bytes():
        var space = b == 32 or b == 10 or b == 9 or b == 13
        if space:
            in_word = False
        elif not in_word:
            in_word = True
            count += 1
    return PythonObject(count)


def mean(values: PythonObject) raises -> PythonObject:
    var n = len(values)
    if n == 0:
        raise Error("mean of empty list")
    var total = 0.0
    for i in range(n):
        total += Float64(py=values[i])
    return PythonObject(total / Float64(n))
