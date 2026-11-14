"""Stage C: pure-Mojo typed handlers on flare (https://github.com/ehsanmok/flare). No Python in the request path.

Run (flare checkout at ~/flare, Mojo from its pixi env):
    cd ~/flare && pixi run mojo -I . -I /path/to/mfastapi/mojo /path/to/mfastapi/mojo/server_c.mojo [port]
The same route shapes as the FastAPI demo (tests/mojo_endpoint): GET /fib/{n}, GET /primes?n=, GET /words?text=.
Bad input becomes a sanitized 400 before the handler runs (typed extractors); FastAPI would answer 422 -- see README.
"""
from std.sys import argv

from flare.prelude import *
from flare.net import SocketAddr
from flare.http import (
    PathInt,
    OptionalQueryInt,
    QueryStr,
    Extracted,
    bad_request,
)
from flare.http.handler import HandlerExtractor
from flare.http.form import urldecode


def fib_rec(n: Int) -> Int:
    if n < 2:
        return n
    return fib_rec(n - 1) + fib_rec(n - 2)


def count_primes(limit: Int) -> Int:
    if limit < 2:
        return 0
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
    return count


def word_count(s: String) -> Int:
    var count = 0
    var in_word = False
    for b in s.as_bytes():
        var space = b == 32 or b == 10 or b == 9 or b == 13
        if space:
            in_word = False
        elif not in_word:
            in_word = True
            count += 1
    return count


@fieldwise_init
struct Fib(HandlerExtractor):
    var n: PathInt["n"]

    def __init__(out self):
        self.n = PathInt["n"]()

    def serve(self, req: Request) raises -> Response:
        var k = self.n.value
        if k < 0 or k > 45:
            return bad_request("n must be between 0 and 45")
        return ok_json(String(fib_rec(k)))


@fieldwise_init
struct Primes(HandlerExtractor):
    var n: OptionalQueryInt["n"]

    def __init__(out self):
        self.n = OptionalQueryInt["n"]()

    def serve(self, req: Request) raises -> Response:
        var limit = 1000
        if self.n.value:
            limit = self.n.value.value()
        if limit < 0 or limit > 100000000:
            return bad_request("n must be between 0 and 100000000")
        return ok_json(String(count_primes(limit)))


@fieldwise_init
struct Words(HandlerExtractor):
    var text: QueryStr["text"]

    def __init__(out self):
        self.text = QueryStr["text"]()

    def serve(self, req: Request) raises -> Response:
        return ok_json(String(word_count(urldecode(self.text.value))))


def main() raises:
    var port = 8080
    var args = argv()
    if len(args) > 1:
        port = Int(args[1])
    var r = Router()
    r.get("/health", health)
    r.get("/fib/:n", Extracted[Fib]())
    r.get("/primes", Extracted[Primes]())
    r.get("/words", Extracted[Words]())
    var srv = HttpServer.bind(SocketAddr.localhost(UInt16(port)))
    print("mfastapi stage C (pure Mojo) listening on 127.0.0.1:" + String(port))
    srv.serve(r^, num_workers=2)


def health(req: Request) raises -> Response:
    return ok_json('{"status":"ok"}')
