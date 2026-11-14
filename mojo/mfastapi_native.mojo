"""Minimal mfastapi native extension, imported from Python as `mfastapi_native`."""
# ホットパス候補: ルート表のパス照合(`/v1/items/{item_id}` と `/v1/items/42`)。
from std.python import PythonObject
from std.python.bindings import PythonModuleBuilder
from std.os import abort


@export
def PyInit_mfastapi_native() abi("C") -> PythonObject:
    try:
        var m = PythonModuleBuilder("mfastapi_native")
        m.def_function[add]("add", docstring="a + b (疎通確認)")
        m.def_function[path_matches]("path_matches", docstring="path_matches(template, path) -> bool")
        return m.finalize()
    except e:
        abort(String("error creating mfastapi_native:", e))


def add(a: PythonObject, b: PythonObject) raises -> PythonObject:
    return Int(py=a) + Int(py=b)


def path_matches(template: PythonObject, path: PythonObject) raises -> PythonObject:
    """Match `{name}` segments against one non-empty path segment, like Starlette."""
    # `{name}` を `/` を含まない非空の1区間として照合する(Starletteの既定と同じ)。
    var t = String(py=template).split("/")
    var p = String(py=path).split("/")
    if len(t) != len(p):
        return PythonObject(False)
    for i in range(len(t)):
        var seg = String(t[i])
        if seg.startswith("{") and seg.endswith("}"):
            if String(p[i]).byte_length() == 0:
                return PythonObject(False)
        elif seg != String(p[i]):
            return PythonObject(False)
    return PythonObject(True)
