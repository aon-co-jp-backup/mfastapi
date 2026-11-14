"""FastAPI-compatible request validation errors (HTTP 422) and OpenAPI 3.1 / docs for flare-based servers (stages B and C).

Shared by server_b.mojo and server_c.mojo. Mirrors what FastAPI+Pydantic return so clients cannot tell the servers apart:
  - invalid int   -> 422 {"detail":[{"type":"int_parsing","loc":["path","n"],"msg":"Input should be a valid integer, unable to parse string as an integer","input":"abc"}]}
  - missing param -> 422 {"detail":[{"type":"missing","loc":["query","text"],"msg":"Field required","input":null}]}
int parsing follows Pydantic lax mode ("5.0", " 5 ", "1_000" accepted); only >18 digits differ (64-bit Int).
"""
from flare.prelude import *
from flare.http.form import urldecode


def json_escape(s: String) -> String:
    var out = List[UInt8]()
    for b in s.as_bytes():
        if b == 34:
            out.append(92)
            out.append(34)
        elif b == 92:
            out.append(92)
            out.append(92)
        elif b == 10:
            out.append(92)
            out.append(110)
        elif b == 13:
            out.append(92)
            out.append(114)
        elif b == 9:
            out.append(92)
            out.append(116)
        elif b < 32:
            var hexd = "0123456789abcdef".as_bytes()
            for c in String("\\u00").as_bytes():
                out.append(c)
            out.append(hexd[Int(b) >> 4])
            out.append(hexd[Int(b) & 15])
        else:
            out.append(b)
    return String(unsafe_from_utf8=Span(out))


def json_response(status: Int, reason: String, body: String) -> Response:
    var resp = Response(status=status, reason=reason, body=List[UInt8](body.as_bytes()))
    try:
        resp.headers.set("Content-Type", "application/json")
    except:
        pass
    return resp^


def html_response(body: String) -> Response:
    var resp = Response(status=200, reason="OK", body=List[UInt8](body.as_bytes()))
    try:
        resp.headers.set("Content-Type", "text/html; charset=utf-8")
    except:
        pass
    return resp^


def parse_int(s: String) -> Optional[Int]:
    """Pydantic lax-mode int from str: surrounding ASCII whitespace, [+-], digits with single "_" between digits,
    optional ".000" fraction (zeros only). Up to 18 integer digits (Int is 64-bit)."""
    var bytes = s.as_bytes()
    var lo = 0
    var hi = len(bytes)
    while lo < hi and (bytes[lo] == 32 or (bytes[lo] >= 9 and bytes[lo] <= 13)):
        lo += 1
    while hi > lo and (bytes[hi - 1] == 32 or (bytes[hi - 1] >= 9 and bytes[hi - 1] <= 13)):
        hi -= 1
    if lo >= hi:
        return Optional[Int]()
    var i = lo
    var neg = False
    if bytes[i] == 43 or bytes[i] == 45:
        neg = bytes[i] == 45
        i += 1
    var v = 0
    var digits = 0
    var prev_us = False
    var seen_digit = False
    while i < hi:
        var c = Int(bytes[i])
        if c >= 48 and c <= 57:
            v = v * 10 + (c - 48)
            digits += 1
            seen_digit = True
            prev_us = False
            if digits > 18:
                return Optional[Int]()
        elif c == 95 and seen_digit and not prev_us:
            prev_us = True
        else:
            break
        i += 1
    if not seen_digit or prev_us:
        return Optional[Int]()
    if i < hi:
        if bytes[i] != 46 or i + 1 >= hi:
            return Optional[Int]()
        i += 1
        while i < hi:
            if bytes[i] != 48:
                return Optional[Int]()
            i += 1
    return Optional[Int](-v if neg else v)


struct Errors(Movable):
    """Collects Pydantic-style validation errors for one request."""

    var items: List[String]

    def __init__(out self):
        self.items = List[String]()

    def int_parsing(mut self, loc: String, name: String, raw: String):
        self.items.append(
            '{"type":"int_parsing","loc":["' + loc + '","' + name
            + '"],"msg":"Input should be a valid integer, unable to parse string as an integer","input":"'
            + json_escape(raw) + '"}'
        )

    def missing(mut self, loc: String, name: String):
        self.items.append(
            '{"type":"missing","loc":["' + loc + '","' + name + '"],"msg":"Field required","input":null}'
        )

    def any(self) -> Bool:
        return len(self.items) > 0

    def response(self) -> Response:
        var body = String('{"detail":[')
        for i in range(len(self.items)):
            if i > 0:
                body += ","
            body += self.items[i]
        body += "]}"
        return json_response(422, "Unprocessable Entity", body)


def path_int(req: Request, name: String, mut errs: Errors) -> Int:
    var raw = String("")
    try:
        raw = urldecode(req.param(name))
    except:
        errs.missing("path", name)
        return 0
    var v = parse_int(raw)
    if not v:
        errs.int_parsing("path", name, raw)
        return 0
    return v.value()


def path_str(req: Request, name: String, mut errs: Errors) -> String:
    try:
        return urldecode(req.param(name))
    except:
        errs.missing("path", name)
        return String("")


def _query_last(req: Request, name: String) raises -> Optional[String]:
    """Last value of query key ``name`` (percent/plus-decoded), like Starlette's QueryParams (duplicates -> last wins).
    A bare key ("?n") counts as present with the empty string (parse_qsl keep_blank_values)."""
    var b = req.url.as_bytes()
    var n = len(b)
    var i = 0
    while i < n and b[i] != 63:  # '?'
        i += 1
    if i >= n:
        return Optional[String]()
    i += 1
    var found = Optional[String]()
    while i < n:  # '#' is not special on the wire (servers pass it through)
        var end = i
        while end < n and b[end] != 38:  # '&'
            end += 1
        var eq = i
        while eq < end and b[eq] != 61:  # '='
            eq += 1
        if end > i:
            var key = String(unsafe_from_utf8=Span(b)[i:eq])
            if urldecode(key) == name:
                if eq < end:
                    found = Optional[String](urldecode(String(unsafe_from_utf8=Span(b)[eq + 1 : end])))
                else:
                    found = Optional[String](String(""))
        i = end + 1
    return found


def query_int(req: Request, name: String, default: Int, mut errs: Errors) raises -> Int:
    """Optional query int with a default (absent -> default; present but invalid -> 422)."""
    var raw = _query_last(req, name)
    if not raw:
        return default
    var v = parse_int(raw.value())
    if not v:
        errs.int_parsing("query", name, raw.value())
        return default
    return v.value()


def query_str(req: Request, name: String, mut errs: Errors) raises -> String:
    """Required query string (absent -> 422 missing; duplicates -> last)."""
    var raw = _query_last(req, name)
    if not raw:
        errs.missing("query", name)
        return String("")
    return raw.value()


# ---------------------------------------------------------------- OpenAPI

comptime INT = 0
comptime STR = 1


struct ParamSpec(Copyable, Movable):
    var name: String
    var loc: String  # "path" | "query"
    var kind: Int  # INT | STR
    var required: Bool
    var default_int: Int  # used when kind == INT and not required

    def __init__(out self, name: String, loc: String, kind: Int, required: Bool = True, default_int: Int = 0):
        self.name = name
        self.loc = loc
        self.kind = kind
        self.required = required
        self.default_int = default_int


struct RouteSpec(Copyable, Movable):
    var path: String  # FastAPI style, e.g. "/fib/{n}"
    var name: String  # operation name, e.g. "fib"
    var params: List[ParamSpec]
    var returns: Int  # INT | STR(= string)
    var returns_json_object: Bool

    def __init__(out self, path: String, name: String, var params: List[ParamSpec], returns: Int = INT):
        self.path = path
        self.name = name
        self.params = params^
        self.returns = returns
        self.returns_json_object = False


def _title(name: String) -> String:
    """Pydantic-style title: 'n' -> 'N', 'user_id' -> 'User Id'."""
    var out = List[UInt8]()
    var up = True
    for b in name.as_bytes():
        if b == 95:
            out.append(32)
            up = True
        elif up and b >= 97 and b <= 122:
            out.append(b - 32)
            up = False
        else:
            out.append(b)
            up = False
    return String(unsafe_from_utf8=Span(out))


def _op_id(name: String, path: String) -> String:
    """FastAPI operationId: (name + path) with every non-alphanumeric character replaced by "_", plus "_get"."""
    var out = List[UInt8]()
    for b in name.as_bytes():
        out.append(b)
    for b in path.as_bytes():
        var alnum = (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
        out.append(b if alnum else 95)
    for b in String("_get").as_bytes():
        out.append(b)
    return String(unsafe_from_utf8=Span(out))


def _param_json(p: ParamSpec) -> String:
    var t = String("integer") if p.kind == INT else String("string")
    var schema = '{"type":"' + t + '"'
    if not p.required and p.kind == INT:
        schema += ',"default":' + String(p.default_int)
    schema += ',"title":"' + _title(p.name) + '"}'
    var req = String("true") if p.required else String("false")
    return '{"name":"' + p.name + '","in":"' + p.loc + '","required":' + req + ',"schema":' + schema + "}"


def openapi_json(routes: List[RouteSpec], title: String = "FastAPI", version: String = "0.1.0") -> String:
    var paths = String("")
    for i in range(len(routes)):
        ref r = routes[i]
        if i > 0:
            paths += ","
        var params = String("")
        for j in range(len(r.params)):
            if j > 0:
                params += ","
            params += _param_json(r.params[j])
        var rt = String("integer") if r.returns == INT else String("string")
        var op = '{"summary":"' + _title(r.name) + '","operationId":"' + _op_id(r.name, r.path) + '"'
        if len(r.params) > 0:
            op += ',"parameters":[' + params + "]"
        op += (
            ',"responses":{"200":{"description":"Successful Response","content":{"application/json":{"schema":{"type":"'
            + rt + '","title":"Response ' + _title(r.name) + '"}}}}'
        )
        if len(r.params) > 0:
            op += (
                ',"422":{"description":"Validation Error","content":{"application/json":{"schema":'
                + '{"$ref":"#/components/schemas/HTTPValidationError"}}}}'
            )
        op += "}}"
        paths += '"' + r.path + '":{"get":' + op + "}"
    return (
        '{"openapi":"3.1.0","info":{"title":"' + title + '","version":"' + version + '"},"paths":{' + paths
        + '},"components":{"schemas":{"HTTPValidationError":{"properties":{"detail":{"items":{"$ref":"#/components/schemas/ValidationError"},"type":"array","title":"Detail"}},"type":"object","title":"HTTPValidationError"},'
        + '"ValidationError":{"properties":{"loc":{"items":{"anyOf":[{"type":"string"},{"type":"integer"}]},"type":"array","title":"Location"},"msg":{"type":"string","title":"Message"},"type":{"type":"string","title":"Error Type"},"input":{"title":"Input"},"ctx":{"type":"object","title":"Context"}},"type":"object","required":["loc","msg","type"],"title":"ValidationError"}}}}'
    )


def docs_html(title: String = "FastAPI") -> String:
    """Swagger UI page (loads swagger-ui-dist from a CDN, like FastAPI's /docs)."""
    return (
        '<!DOCTYPE html><html><head><link type="text/css" rel="stylesheet" '
        + 'href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css"><title>' + title
        + ' - Swagger UI</title></head><body><div id="swagger-ui"></div>'
        + '<script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js"></script>'
        + '<script>const ui = SwaggerUIBundle({url: "/openapi.json", dom_id: "#swagger-ui", presets: '
        + "[SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset], layout: "
        + '"BaseLayout", deepLinking: true})</script></body></html>'
    )
