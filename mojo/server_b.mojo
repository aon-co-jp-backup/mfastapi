"""Stage B: hybrid. Mojo (flare) owns HTTP and routing; user handlers written in Python are called across the boundary.

Routes:
  GET /py/hello/:name   -> Python  pyhandlers.greet(name)
  GET /py/fib/:n        -> Python  pyhandlers.fib(n)         (slow on purpose: shows the Python cost)
  GET /py/stats?csv=    -> Python  pyhandlers.stats(csv)
  GET /fib/:n           -> Mojo    (same server, no Python)
Python is embedded in this process (one interpreter, GIL). Keep num_workers=1 unless the GIL is handled (see README).
Run: MOJO_PYTHON_LIBRARY=<libpython3.x.so> ./server_b <port> <dir-with-pyhandlers.py>
"""
from std.sys import argv
from std.python import Python, PythonObject

from flare.prelude import *
from flare.net import SocketAddr
from flare.http import PathInt, PathStr, QueryStr, Extracted, bad_request
from flare.http.handler import HandlerExtractor
from flare.http.form import urldecode


def fib_rec(n: Int) -> Int:
    if n < 2:
        return n
    return fib_rec(n - 1) + fib_rec(n - 2)


def call_py(fname: String, arg: String) raises -> Response:
    var m = Python.import_module("pyhandlers")
    var out = m.__getattr__(fname)(arg)
    return ok_json(String(py=out))


@fieldwise_init
struct PyHello(HandlerExtractor):
    var name: PathStr["name"]

    def __init__(out self):
        self.name = PathStr["name"]()

    def serve(self, req: Request) raises -> Response:
        return call_py("greet", self.name.value)


@fieldwise_init
struct PyFib(HandlerExtractor):
    var n: PathInt["n"]

    def __init__(out self):
        self.n = PathInt["n"]()

    def serve(self, req: Request) raises -> Response:
        if self.n.value < 0 or self.n.value > 35:
            return bad_request("n must be between 0 and 35")
        return call_py("fib", String(self.n.value))


@fieldwise_init
struct PyStats(HandlerExtractor):
    var csv: QueryStr["csv"]

    def __init__(out self):
        self.csv = QueryStr["csv"]()

    def serve(self, req: Request) raises -> Response:
        return call_py("stats", urldecode(self.csv.value))


@fieldwise_init
struct MojoFib(HandlerExtractor):
    var n: PathInt["n"]

    def __init__(out self):
        self.n = PathInt["n"]()

    def serve(self, req: Request) raises -> Response:
        if self.n.value < 0 or self.n.value > 45:
            return bad_request("n must be between 0 and 45")
        return ok_json(String(fib_rec(self.n.value)))


def health(req: Request) raises -> Response:
    return ok_json('{"status":"ok"}')


def main() raises:
    var port = 8080
    var args = argv()
    if len(args) > 1:
        port = Int(args[1])
    if len(args) > 2:
        Python.add_to_path(String(args[2]))
    var r = Router()
    r.get("/health", health)
    r.get("/py/hello/:name", Extracted[PyHello]())
    r.get("/py/fib/:n", Extracted[PyFib]())
    r.get("/py/stats", Extracted[PyStats]())
    r.get("/fib/:n", Extracted[MojoFib]())
    var srv = HttpServer.bind(SocketAddr.localhost(UInt16(port)))
    print("mfastapi stage B (Mojo HTTP + Python handlers) on 127.0.0.1:" + String(port))
    srv.serve(r^, num_workers=1)
