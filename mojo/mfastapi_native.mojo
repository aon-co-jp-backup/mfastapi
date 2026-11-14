"""Mojo extension module for Python 3: Starlette-compatible path matching and a compiled RouteTable."""
from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder
from std.os import abort

from mfastapi_match import Ctx, FPtr, K_FLOAT, K_INT, K_UUID, match_from
from mfastapi_table import RouteTable, first_match, first_match_from, first_match_linear


@export
def PyInit_mfastapi_native() abi("C") -> PythonObject:
    try:
        var m = PythonModuleBuilder("mfastapi_native")
        m.def_function[add]("add", docstring="a + b (smoke test)")
        m.def_function[path_matches]("path_matches", docstring="path_matches(template, path) -> bool")
        _ = (
            m.add_type[PyRouteTable]("RouteTable")
            .def_py_init[PyRouteTable.py_init]()
            .def_method[PyRouteTable.first_match]("first_match")
            .def_method[PyRouteTable.match]("match")
            .def_method[PyRouteTable.first_match_from]("first_match_from")
            .def_method[PyRouteTable.first_match_linear]("first_match_linear")
            .def_method[PyRouteTable.size]("size")
        )
        return m.finalize()
    except e:
        abort(String("error creating mfastapi_native:", e))


def utf8_of(o: PythonObject) raises -> StringSpan[ImmutAnyOrigin]:
    """Zero-copy view of a Python str's cached UTF-8 buffer (valid while `o` is alive)."""
    ref cpy = Python().cpython()
    var sp = cpy.PyUnicode_AsUTF8AndSize(o._obj_ptr)
    if not sp:
        raise Error("expected str")
    return sp.value()


def add(a: PythonObject, b: PythonObject) raises -> PythonObject:
    return Int(py=a) + Int(py=b)


def path_matches(template: PythonObject, path: PythonObject) raises -> PythonObject:
    """Starlette-compatible match of one template against a path."""
    var t = utf8_of(template)
    var p = utf8_of(path)
    var c = Ctx(
        rebind[FPtr](t.unsafe_ptr()),
        t.byte_length(),
        rebind[FPtr](p.unsafe_ptr()),
        p.byte_length(),
    )
    var r = match_from(c, 0, 0)
    if r == -1:
        raise Error("unknown path convertor in template")
    if r == -2:
        raise Error("path matching gave up (backtracking budget)")
    return PythonObject(r == 1)


struct PyRouteTable(Movable, Writable):
    var table: RouteTable
    # 毎回importや文字列生成をしないよう、パラメータ名のstrと変換関数を保持する
    var keys: List[PythonObject]
    var int_fn: PythonObject
    var float_fn: PythonObject
    var uuid_cls: PythonObject

    def __init__(out self, var t: RouteTable) raises:
        var keys = List[PythonObject]()
        for i in range(len(t.pnames)):
            keys.append(PythonObject(t.pnames[i]))
        self.keys = keys^
        var builtins = Python.import_module("builtins")
        self.int_fn = builtins.int
        self.float_fn = builtins.float
        self.uuid_cls = Python.import_module("uuid").UUID
        self.table = t^

    @staticmethod
    def py_init(
        out self: PyRouteTable, args: PythonObject, kwargs: PythonObject
    ) raises:
        if len(args) != 1:
            raise Error("RouteTable(templates) takes exactly 1 argument")
        var t = RouteTable()
        var lst = args[0]
        for i in range(len(lst)):
            t.add(String(py=lst[i]))
        t.freeze()
        self = Self(t^)

    @staticmethod
    def first_match(
        py_self: PythonObject, path: PythonObject
    ) raises -> PythonObject:
        """Index of the first template matching `path`, or -1."""
        var self_ptr = py_self.downcast_value_ptr[Self]()
        var p = utf8_of(path)
        var r = first_match(
            self_ptr[].table, rebind[FPtr](p.unsafe_ptr()), p.byte_length()
        )
        if r == -3:
            raise Error("path matching gave up (backtracking budget)")
        return PythonObject(r)

    @staticmethod
    def first_match_from(
        py_self: PythonObject, path: PythonObject, start: PythonObject
    ) raises -> PythonObject:
        """Index (>= start) of the first template matching `path`, or -1."""
        var self_ptr = py_self.downcast_value_ptr[Self]()
        var p = utf8_of(path)
        var r = first_match_from(
            self_ptr[].table, rebind[FPtr](p.unsafe_ptr()), p.byte_length(), Int(py=start)
        )
        if r == -3:
            raise Error("path matching gave up (backtracking budget)")
        return PythonObject(r)

    @staticmethod
    def first_match_linear(
        py_self: PythonObject, path: PythonObject
    ) raises -> PythonObject:
        """Same result as first_match, using the old linear scan (for verification and benchmarks)."""
        var self_ptr = py_self.downcast_value_ptr[Self]()
        var p = utf8_of(path)
        var r = first_match_linear(
            self_ptr[].table, rebind[FPtr](p.unsafe_ptr()), p.byte_length()
        )
        if r == -3:
            raise Error("path matching gave up (backtracking budget)")
        return PythonObject(r)

    @staticmethod
    def match(
        py_self: PythonObject, path: PythonObject
    ) raises -> PythonObject:
        """Return None, or (index, path_params) with Starlette-style converted values."""
        var self_ptr = py_self.downcast_value_ptr[Self]()
        var p = utf8_of(path)
        var pp = rebind[FPtr](p.unsafe_ptr())
        var r = first_match(self_ptr[].table, pp, p.byte_length())
        if r == -3:
            raise Error("path matching gave up (backtracking budget)")
        if r < 0:
            return PythonObject(None)
        ref t = self_ptr[].table
        ref me = self_ptr[]
        var params = Python.dict()
        var pb = Int(t.pbase[r])
        for j in range(Int(t.pcount[r])):
            var s0 = Int(t.bcaps[2 * j])
            var e0 = Int(t.bcaps[2 * j + 1])
            var kind = Int(t.pkinds[pb + j])
            var val: PythonObject
            if kind == K_INT and e0 - s0 <= 18:
                var n = 0
                for q in range(s0, e0):
                    n = n * 10 + Int(pp.unsafe_offset(q)[] - 48)
                val = PythonObject(n)
            else:
                var text = PythonObject(
                    String(unsafe_from_utf8=Span(unsafe_ptr=pp.unsafe_offset(s0), length=e0 - s0))
                )
                if kind == K_INT:
                    val = me.int_fn(text)
                elif kind == K_FLOAT:
                    val = me.float_fn(text)
                elif kind == K_UUID:
                    val = me.uuid_cls(text)
                else:
                    val = text
            params[me.keys[pb + j]] = val
        return Python.tuple(PythonObject(r), params)

    @staticmethod
    def size(py_self: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        return PythonObject(self_ptr[].table.count)

    def write_to(self, mut writer: Some[Writer]):
        t"RouteTable({self.table.count} routes)".write_to(writer)
