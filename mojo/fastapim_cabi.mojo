"""C ABI exports of fastapim native functions, callable from any Python via ctypes."""

from fastapim_match import Ptr, FPtr, Ctx, match_from


@export
def fastapim_abi_version() abi("C") -> Int32:
    return 1


@export
def fastapim_add(a: Int64, b: Int64) abi("C") -> Int64:
    return a + b


@export
def fastapim_path_matches(
    tpl: Ptr, tpl_len: Int64, path: Ptr, path_len: Int64
) abi("C") -> Int32:
    if tpl_len < 0 or path_len < 0:
        return 0
    var c = Ctx(rebind[FPtr](tpl), Int(tpl_len), rebind[FPtr](path), Int(path_len))
    return Int32(match_from(c, 0, 0))


# ルート表をまとめて照合する(c/fastapim_cabi.c と同じ仕様)。
@export
def fastapim_route_first_match(
    tpls: Ptr, tpls_len: Int64, path: Ptr, path_len: Int64
) abi("C") -> Int32:
    if tpls_len < 0 or path_len < 0:
        return -1
    var n = Int(tpls_len)
    var start = 0
    var idx = 0
    for i in range(n + 1):
        if i == n or tpls.unsafe_offset(i)[] == 10:
            var c = Ctx(
                rebind[FPtr](tpls.unsafe_offset(start)),
                i - start,
                rebind[FPtr](path),
                Int(path_len),
            )
            var r = match_from(c, 0, 0)
            if r == 1:
                return Int32(idx)
            if r == -1:
                return -2
            if r == -2:
                return -3
            idx += 1
            start = i + 1
    return -1
