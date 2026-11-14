"""C ABI exports of mfastapi native functions, callable from any Python via ctypes."""

# mfastapi_path_matches はStarletteのcompile_path()/re.matchと同じ意味(c/mfastapi_cabi.c と同一ロジック)。
# 戻り値: 1=一致, 0=不一致, -1=未知の型名, -2=バックトラック上限で断念。
comptime K_STR = 0
comptime K_PATH = 1
comptime K_INT = 2
comptime K_FLOAT = 3
comptime K_UUID = 4
comptime BUDGET = 200000
comptime Ptr = Pointer[UInt8, MutAnyOrigin]
comptime FPtr = Pointer[UInt8, MutUntrackedOrigin]


@always_inline
def is_alpha(c: UInt8) -> Bool:
    return (c >= 97 and c <= 122) or (c >= 65 and c <= 90) or c == 95


@always_inline
def is_digit(c: UInt8) -> Bool:
    return c >= 48 and c <= 57


@always_inline
def is_alnum(c: UInt8) -> Bool:
    return is_alpha(c) or is_digit(c)


@always_inline
def is_hex(c: UInt8) -> Bool:
    return is_digit(c) or (c >= 97 and c <= 102) or (c >= 65 and c <= 70)


struct Ctx(Copyable, Movable):
    var t: FPtr
    var tl: Int
    var p: FPtr
    var pl: Int
    var steps: Int

    def __init__(out self, t: FPtr, tl: Int, p: FPtr, pl: Int):
        self.t = t
        self.tl = tl
        self.p = p
        self.pl = pl
        self.steps = 0

    @always_inline
    def tb(self, i: Int) -> UInt8:
        return self.t.unsafe_offset(i)[]

    @always_inline
    def pb(self, i: Int) -> UInt8:
        return self.p.unsafe_offset(i)[]


# 0=リテラル, 1=有効なパラメータ(next, kind を返す), -1=型名が不明
def parse_param(c: Ctx, i: Int) -> Tuple[Int, Int, Int]:
    var j = i + 1
    if j >= c.tl or not is_alpha(c.tb(j)):
        return (0, 0, 0)
    while j < c.tl and is_alnum(c.tb(j)):
        j += 1
    if j < c.tl and c.tb(j) == 58:  # ':'
        var s = j + 1
        var e = s
        if e >= c.tl or not is_alpha(c.tb(e)):
            return (0, 0, 0)
        while e < c.tl and is_alnum(c.tb(e)):
            e += 1
        if e >= c.tl or c.tb(e) != 125:
            return (0, 0, 0)
        var n = e - s
        var kind = -1
        if n == 3 and c.tb(s) == 115 and c.tb(s + 1) == 116 and c.tb(s + 2) == 114:
            kind = K_STR
        elif n == 4 and c.tb(s) == 112 and c.tb(s + 1) == 97 and c.tb(s + 2) == 116 and c.tb(s + 3) == 104:
            kind = K_PATH
        elif n == 3 and c.tb(s) == 105 and c.tb(s + 1) == 110 and c.tb(s + 2) == 116:
            kind = K_INT
        elif n == 5 and c.tb(s) == 102 and c.tb(s + 1) == 108 and c.tb(s + 2) == 111 and c.tb(s + 3) == 97 and c.tb(s + 4) == 116:
            kind = K_FLOAT
        elif n == 4 and c.tb(s) == 117 and c.tb(s + 1) == 117 and c.tb(s + 2) == 105 and c.tb(s + 3) == 100:
            kind = K_UUID
        if kind < 0:
            return (-1, 0, 0)
        return (1, e + 1, kind)
    if j >= c.tl or c.tb(j) != 125:  # '}'
        return (0, 0, 0)
    return (1, j + 1, K_STR)


def try_ends(mut c: Ctx, ti: Int, hi: Int, lo: Int) -> Int:
    # 長い方から短い方へ(正規表現の貪欲+バックトラックと同じ順)。UTF-8の文字の途中では区切らない。
    var e = hi
    while e >= lo:
        if e < c.pl and (c.pb(e) & 0xC0) == 0x80:
            e -= 1
            continue
        c.steps += 1
        if c.steps > BUDGET:
            return -2
        var r = match_from(c, ti, e)
        if r != 0:
            return r
        e -= 1
    return 0


def match_from(mut c: Ctx, ti_in: Int, pi_in: Int) -> Int:
    var ti = ti_in
    var pi = pi_in
    while ti < c.tl:
        var ch = c.tb(ti)
        if ch == 123:  # '{'
            var pr = parse_param(c, ti)
            if pr[0] < 0:
                return -1
            if pr[0] > 0:
                var nx = pr[1]
                var kind = pr[2]
                var e = pi
                if kind == K_STR:
                    while e < c.pl and c.pb(e) != 47:
                        e += 1
                    return try_ends(c, nx, e, pi + 1) if e > pi else 0
                elif kind == K_PATH:
                    while e < c.pl and c.pb(e) != 10:
                        e += 1
                    return try_ends(c, nx, e, pi)
                elif kind == K_INT:
                    while e < c.pl and is_digit(c.pb(e)):
                        e += 1
                    return try_ends(c, nx, e, pi + 1) if e > pi else 0
                elif kind == K_FLOAT:
                    var d1 = pi
                    while d1 < c.pl and is_digit(c.pb(d1)):
                        d1 += 1
                    if d1 == pi:
                        return 0
                    if d1 + 1 < c.pl and c.pb(d1) == 46 and is_digit(c.pb(d1 + 1)):
                        var d2 = d1 + 1
                        while d2 < c.pl and is_digit(c.pb(d2)):
                            d2 += 1
                        var r = try_ends(c, nx, d2, d1 + 2)
                        if r != 0:
                            return r
                    return try_ends(c, nx, d1, pi + 1)
                else:  # K_UUID: 8-4-4-4-12、'-'は省略可
                    var q = pi
                    for k in range(5):
                        var n = 12 if k == 4 else (8 if k == 0 else 4)
                        if k > 0 and q < c.pl and c.pb(q) == 45:
                            q += 1
                        for _ in range(n):
                            if q >= c.pl or not is_hex(c.pb(q)):
                                return 0
                            q += 1
                    pi = q
                    ti = nx
                    continue
        if pi >= c.pl or c.pb(pi) != ch:
            return 0
        ti += 1
        pi += 1
    # '$' : 末尾、または末尾の改行1つ手前
    if pi == c.pl or (pi == c.pl - 1 and c.pb(pi) == 10):
        return 1
    return 0


@export
def mfastapi_abi_version() abi("C") -> Int32:
    return 1


@export
def mfastapi_add(a: Int64, b: Int64) abi("C") -> Int64:
    return a + b


@export
def mfastapi_path_matches(
    tpl: Ptr, tpl_len: Int64, path: Ptr, path_len: Int64
) abi("C") -> Int32:
    if tpl_len < 0 or path_len < 0:
        return 0
    var c = Ctx(rebind[FPtr](tpl), Int(tpl_len), rebind[FPtr](path), Int(path_len))
    return Int32(match_from(c, 0, 0))


# ルート表をまとめて照合する(c/mfastapi_cabi.c と同じ仕様)。
@export
def mfastapi_route_first_match(
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
