"""C ABI exports of mfastapi native functions, callable from any Python via ctypes."""


@export
def mfastapi_abi_version() abi("C") -> Int32:
    return 1


@export
def mfastapi_add(a: Int64, b: Int64) abi("C") -> Int64:
    return a + b


# 文字列は(バイト列ポインタ, バイト長)で受け取る。Pythonの版に依存しない。
@export
def mfastapi_path_matches(
    tpl: Pointer[UInt8, MutAnyOrigin],
    tpl_len: Int64,
    path: Pointer[UInt8, MutAnyOrigin],
    path_len: Int64,
) abi("C") -> Int32:
    """Return 1 when `path` matches `tpl` (`{name}` = one non-empty segment), else 0."""
    var i = 0
    var j = 0
    var tl = Int(tpl_len)
    var pl = Int(path_len)
    while True:
        # 次の区間 [i, ie) と [j, je) を取り出す。
        var ie = i
        while ie < tl and tpl.unsafe_offset(ie)[] != 47:
            ie += 1
        var je = j
        while je < pl and path.unsafe_offset(je)[] != 47:
            je += 1
        var is_param = ie - i >= 2 and tpl.unsafe_offset(i)[] == 123 and tpl.unsafe_offset(ie - 1)[] == 125
        if is_param:
            if je == j:
                return 0
        else:
            if ie - i != je - j:
                return 0
            for k in range(ie - i):
                if tpl.unsafe_offset(i + k)[] != path.unsafe_offset(j + k)[]:
                    return 0
        var t_end = ie >= tl
        var p_end = je >= pl
        if t_end or p_end:
            return 1 if (t_end and p_end) else 0
        i = ie + 1
        j = je + 1
