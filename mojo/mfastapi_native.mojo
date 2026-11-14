"""Mojo extension module for Python 3: Starlette-compatible path matching and a compiled RouteTable."""
from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder
from std.os import abort

from mfastapi_match import Ctx, FPtr, match_from
from mfastapi_table import RouteTable, first_match


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

    def __init__(out self, var t: RouteTable):
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
    def size(py_self: PythonObject) raises -> PythonObject:
        var self_ptr = py_self.downcast_value_ptr[Self]()
        return PythonObject(self_ptr[].table.count)

    def write_to(self, mut writer: Some[Writer]):
        t"RouteTable({self.table.count} routes)".write_to(writer)
