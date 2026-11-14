"""Stage B: hybrid. Mojo (flare) owns HTTP, routing, validation (FastAPI-compatible 422) and OpenAPI; user handlers written in Python are
called across the boundary after validation.

Routes:
  GET /py/hello/{name}   -> Python  pyhandlers.greet(name)
  GET /py/fib/{n}        -> Python  pyhandlers.fib(n)         (slow on purpose: shows the Python cost)
  GET /py/stats?csv=     -> Python  pyhandlers.stats(csv)
  GET /fib/{n}           -> Mojo    (same server, no Python)
  GET /openapi.json, /docs
Python is embedded in this process (one interpreter, GIL). Keep num_workers=1 unless the GIL is handled (see README).
Run: MOJO_PYTHON_LIBRARY=<libpython3.x.so> ./server_b <port> <dir-with-pyhandlers.py>
"""
from std.sys import argv
from std.python import Python, PythonObject

from flare.prelude import *
from flare.net import SocketAddr

from mfastapi_web import (
    Errors,
    ParamSpec,
    RouteSpec,
    INT,
    STR,
    path_int,
    path_str,
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


def call_py(fname: String, arg: String) raises -> Response:
    var m = Python.import_module("pyhandlers")
    var out = m.__getattr__(fname)(arg)
    return ok_json(String(py=out))


def http_400(msg: String) -> Response:
    return json_response(400, "Bad Request", '{"detail":"' + msg + '"}')


def py_hello(req: Request) raises -> Response:
    var errs = Errors()
    var name = path_str(req, "name", errs)
    if errs.any():
        return errs.response()
    return call_py("greet", name)


def py_fib(req: Request) raises -> Response:
    var errs = Errors()
    var n = path_int(req, "n", errs)
    if errs.any():
        return errs.response()
    if n < 0 or n > 35:
        return http_400("n must be between 0 and 35")
    return call_py("fib", String(n))


def py_stats(req: Request) raises -> Response:
    var errs = Errors()
    var csv = query_str(req, "csv", errs)
    if errs.any():
        return errs.response()
    return call_py("stats", csv)


def mojo_fib(req: Request) raises -> Response:
    var errs = Errors()
    var n = path_int(req, "n", errs)
    if errs.any():
        return errs.response()
    if n < 0 or n > 45:
        return http_400("n must be between 0 and 45")
    return ok_json(String(fib_rec(n)))


def health(req: Request) raises -> Response:
    return ok_json('{"status":"ok"}')


def specs() -> List[RouteSpec]:
    var routes = List[RouteSpec]()
    var a = List[ParamSpec]()
    a.append(ParamSpec("name", "path", STR))
    routes.append(RouteSpec("/py/hello/{name}", "py_hello", a^, STR))
    var b = List[ParamSpec]()
    b.append(ParamSpec("n", "path", INT))
    routes.append(RouteSpec("/py/fib/{n}", "py_fib", b^, INT))
    var c = List[ParamSpec]()
    c.append(ParamSpec("csv", "query", STR))
    routes.append(RouteSpec("/py/stats", "py_stats", c^, STR))
    var d = List[ParamSpec]()
    d.append(ParamSpec("n", "path", INT))
    routes.append(RouteSpec("/fib/{n}", "fib", d^, INT))
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
    if len(args) > 2:
        Python.add_to_path(String(args[2]))
    var r = Router()
    r.get("/health", health)
    r.get("/py/hello/:name", py_hello)
    r.get("/py/fib/:n", py_fib)
    r.get("/py/stats", py_stats)
    r.get("/fib/:n", mojo_fib)
    r.get("/openapi.json", openapi)
    r.get("/docs", docs)
    var srv = HttpServer.bind(SocketAddr.localhost(UInt16(port)))
    print("mfastapi stage B (Mojo HTTP + Python handlers) on 127.0.0.1:" + String(port))
    srv.serve(r^, num_workers=1)
