"""Stage C: pure-Mojo handlers on flare (https://github.com/ehsanmok/flare). No Python in the request path.

Run (flare checkout at ~/flare, Mojo from its pixi env):
    cd ~/flare && pixi run mojo -I . -I /path/to/mfastapi/mojo /path/to/mfastapi/mojo/server_c.mojo [port]
Same routes as the FastAPI demo (tests/mojo_endpoint): GET /fib/{n}, /primes?n=, /words?text=.
Validation errors are FastAPI-compatible 422 responses; /openapi.json and /docs are served (see mfastapi_web.mojo).
"""
from std.sys import argv

from flare.prelude import *
from flare.net import SocketAddr

from mfastapi_web import (
    Errors,
    ParamSpec,
    RouteSpec,
    INT,
    STR,
    path_int,
    query_int,
    query_str,
    openapi_json,
    docs_html,
    json_response,
    html_response,
)


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


def http_400(msg: String) -> Response:
    return json_response(400, "Bad Request", '{"detail":"' + msg + '"}')


def fib_handler(req: Request) raises -> Response:
    var errs = Errors()
    var k = path_int(req, "n", errs)
    if errs.any():
        return errs.response()
    if k < 0 or k > 45:
        return http_400("n must be between 0 and 45")
    return ok_json(String(fib_rec(k)))


def primes_handler(req: Request) raises -> Response:
    var errs = Errors()
    var limit = query_int(req, "n", 1000, errs)
    if errs.any():
        return errs.response()
    if limit < 0 or limit > 100000000:
        return http_400("n must be between 0 and 100000000")
    return ok_json(String(count_primes(limit)))


def words_handler(req: Request) raises -> Response:
    var errs = Errors()
    var text = query_str(req, "text", errs)
    if errs.any():
        return errs.response()
    return ok_json(String(word_count(text)))


def health(req: Request) raises -> Response:
    return ok_json('{"status":"ok"}')


def specs() -> List[RouteSpec]:
    var routes = List[RouteSpec]()
    var p1 = List[ParamSpec]()
    p1.append(ParamSpec("n", "path", INT))
    routes.append(RouteSpec("/fib/{n}", "fib", p1^))
    var p2 = List[ParamSpec]()
    p2.append(ParamSpec("n", "query", INT, required=False, default_int=1000))
    routes.append(RouteSpec("/primes", "primes", p2^))
    var p3 = List[ParamSpec]()
    p3.append(ParamSpec("text", "query", STR))
    routes.append(RouteSpec("/words", "words", p3^))
    return routes^


def openapi(req: Request) raises -> Response:
    return json_response(200, "OK", openapi_json(specs()))


def docs(req: Request) raises -> Response:
    return html_response(docs_html())


def main() raises:
    var port = 8080
    var args = argv()
    if len(args) > 1:
        port = Int(args[1])
    var r = Router()
    r.get("/health", health)
    r.get("/fib/:n", fib_handler)
    r.get("/primes", primes_handler)
    r.get("/words", words_handler)
    r.get("/openapi.json", openapi)
    r.get("/docs", docs)
    var srv = HttpServer.bind(SocketAddr.localhost(UInt16(port)))
    print("mfastapi stage C (pure Mojo) listening on 127.0.0.1:" + String(port))
    srv.serve(r^, num_workers=2)
