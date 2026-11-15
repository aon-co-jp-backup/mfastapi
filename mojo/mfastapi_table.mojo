"""Pre-compiled route table: templates are parsed once, then matched without re-parsing."""
from mfastapi_match import (
    Ctx,
    FPtr,
    K_FLOAT,
    K_INT,
    K_PATH,
    K_STR,
    K_UUID,
    BUDGET,
    is_digit,
    is_hex,
    parse_param,
)

comptime IPtr = Pointer[Int32, MutUntrackedOrigin]
comptime MAX_PARAMS = 16
comptime LINEAR_MAX = 8
comptime LIT = -1  # トークン種別: リテラル(それ以外はK_*)


struct RouteTable(Movable, Writable):
    # ops: ルートごとに [kind, a, b] の3つ組を並べる。リテラルは kind=LIT, a=lits内の位置, b=長さ。
    var ops: List[Int32]
    var lits: List[UInt8]
    var base: List[Int32]  # 各ルートの ops 内の開始位置
    var ntok: List[Int32]
    var count: Int
    # パラメータ名・種別(ルートごとに連続して並べる)
    var pnames: List[String]
    var pkinds: List[Int32]
    var pbase: List[Int32]
    var pcount: List[Int32]
    var caps: List[Int32]  # 直近の照合で得た [開始,終端] の並び(GILの下で使い回す)
    # 先頭リテラルのtrie。ノード0が根。子は「最初の子+次の兄弟」の連結リスト。
    var t_child: List[Int32]
    var t_next: List[Int32]
    var t_byte: List[UInt8]
    var t_routes: List[List[Int32]]  # 構築中: このノードで先頭リテラルが終わるルート番号(昇順)
    var t_rstart: List[Int32]  # 凍結後: rlist内の開始位置
    var t_rlen: List[Int32]
    var rlist: List[Int32]
    var frozen: Bool
    var bcaps: List[Int32]  # 最終的に採用したルートのキャプチャ(後続の試行で上書きされないよう退避)

    def __init__(out self):
        self.ops = List[Int32]()
        self.lits = List[UInt8]()
        self.base = List[Int32]()
        self.ntok = List[Int32]()
        self.count = 0
        self.pnames = List[String]()
        self.pkinds = List[Int32]()
        self.pbase = List[Int32]()
        self.pcount = List[Int32]()
        self.caps = List[Int32](length=2 * MAX_PARAMS, fill=0)
        self.t_child = List[Int32]()
        self.t_next = List[Int32]()
        self.t_byte = List[UInt8]()
        self.t_routes = List[List[Int32]]()
        self.t_rstart = List[Int32]()
        self.t_rlen = List[Int32]()
        self.rlist = List[Int32]()
        self.frozen = False
        self.bcaps = List[Int32](length=2 * MAX_PARAMS, fill=0)
        _ = self._new_node(0)  # 根

    def write_to(self, mut writer: Some[Writer]):
        t"RouteTable({self.count} routes)".write_to(writer)

    def _new_node(mut self, b: UInt8) -> Int:
        self.t_child.append(-1)
        self.t_next.append(-1)
        self.t_byte.append(b)
        self.t_routes.append(List[Int32]())
        return len(self.t_byte) - 1

    def _trie_insert(mut self, route: Int, off: Int, ln: Int):
        var node = 0
        for k in range(ln):
            var b = self.lits[off + k]
            var ch = Int(self.t_child[node])
            while ch >= 0 and self.t_byte[ch] != b:
                ch = Int(self.t_next[ch])
            if ch < 0:
                ch = self._new_node(b)
                self.t_next[ch] = self.t_child[node]
                self.t_child[node] = Int32(ch)
            node = ch
        self.t_routes[node].append(Int32(route))

    def freeze(mut self):
        """trieのルート番号リストを1本の配列に平坦化する(全ルート登録後に1回呼ぶ)。"""
        for i in range(len(self.t_routes)):
            self.t_rstart.append(Int32(len(self.rlist)))
            self.t_rlen.append(Int32(len(self.t_routes[i])))
            for j in range(len(self.t_routes[i])):
                self.rlist.append(self.t_routes[i][j])
        self.frozen = True

    def add(mut self, tpl: String) raises:
        var c = Ctx(
            rebind[FPtr](tpl.unsafe_ptr()),
            tpl.byte_length(),
            rebind[FPtr](tpl.unsafe_ptr()),
            0,
        )
        self.base.append(Int32(len(self.ops)))
        self.pbase.append(Int32(len(self.pnames)))
        var np = 0
        var n = 0
        var i = 0
        var lit_start = len(self.lits)
        while i < c.tl:
            if c.tb(i) == 123:
                var pr = parse_param(c, i)
                if pr[0] < 0:
                    raise Error("unknown path convertor in template: " + tpl)
                if pr[0] > 0:
                    if len(self.lits) > lit_start:
                        self.ops.append(Int32(LIT))
                        self.ops.append(Int32(lit_start))
                        self.ops.append(Int32(len(self.lits) - lit_start))
                        n += 1
                        lit_start = len(self.lits)
                    # 名前(コロンの手前まで)を取り出して重複を拒否する(Starletteと同じ)
                    var ne = i + 1
                    while ne < c.tl and c.tb(ne) != 58 and c.tb(ne) != 125:
                        ne += 1
                    var name = String(unsafe_from_utf8=Span(unsafe_ptr=tpl.unsafe_ptr().unsafe_offset(i + 1), length=ne - i - 1))
                    for q in range(np):
                        if self.pnames[len(self.pnames) - np + q] == name:
                            raise Error("Duplicated param name " + name + " at path " + tpl)
                    if np >= MAX_PARAMS:
                        raise Error("too many path params (max 16): " + tpl)
                    self.pnames.append(name)
                    self.pkinds.append(Int32(pr[2]))
                    self.ops.append(Int32(pr[2]))
                    self.ops.append(0)
                    self.ops.append(Int32(np))  # パラメータの序数
                    np += 1
                    n += 1
                    i = pr[1]
                    continue
            self.lits.append(c.tb(i))
            i += 1
        if len(self.lits) > lit_start:
            self.ops.append(Int32(LIT))
            self.ops.append(Int32(lit_start))
            self.ops.append(Int32(len(self.lits) - lit_start))
            n += 1
        self.ntok.append(Int32(n))
        self.pcount.append(Int32(np))
        # 先頭がリテラルならその文字列で、なければ根に登録する
        var b0 = Int(self.base[self.count])
        if n > 0 and Int(self.ops[b0]) == LIT:
            self._trie_insert(self.count, Int(self.ops[b0 + 1]), Int(self.ops[b0 + 2]))
        else:
            self.t_routes[0].append(Int32(self.count))
        self.count += 1


def try_ends_t(
    ops: IPtr,
    lits: FPtr,
    caps: IPtr,
    k: Int,
    start: Int,
    base: Int,
    nt: Int,
    ti: Int,
    p: FPtr,
    pl: Int,
    hi: Int,
    lo: Int,
    mut steps: Int,
) -> Int:
    var e = hi
    while e >= lo:
        if e < pl and (p.unsafe_offset(e)[] & 0xC0) == 0x80:
            e -= 1
            continue
        steps += 1
        if steps > BUDGET:
            return -2
        caps.unsafe_offset(2 * k)[] = Int32(start)
        caps.unsafe_offset(2 * k + 1)[] = Int32(e)
        var r = match_t(ops, lits, caps, base, nt, ti, p, pl, e, steps)
        if r != 0:
            return r
        e -= 1
    return 0


def match_t(
    ops: IPtr,
    lits: FPtr,
    caps: IPtr,
    base: Int,
    nt: Int,
    ti_in: Int,
    p: FPtr,
    pl: Int,
    pi_in: Int,
    mut steps: Int,
) -> Int:
    var ti = ti_in
    var pi = pi_in
    while ti < nt:
        var o = base + ti * 3
        var kind = Int(ops.unsafe_offset(o)[])
        if kind == LIT:
            var off = Int(ops.unsafe_offset(o + 1)[])
            var ln = Int(ops.unsafe_offset(o + 2)[])
            if pl - pi < ln:
                return 0
            for k in range(ln):
                if lits.unsafe_offset(off + k)[] != p.unsafe_offset(pi + k)[]:
                    return 0
            pi += ln
            ti += 1
            continue
        var e = pi
        var k = Int(ops.unsafe_offset(o + 2)[])
        if kind == K_STR:
            while e < pl and p.unsafe_offset(e)[] != 47:
                e += 1
            if e == pi:
                return 0
            if ti + 1 == nt and e == pl:  # 末尾のstr: 取り切って終わり(分割の余地なし)
                caps.unsafe_offset(2 * k)[] = Int32(pi)
                caps.unsafe_offset(2 * k + 1)[] = Int32(e)
                return 1
            return try_ends_t(ops, lits, caps, k, pi, base, nt, ti + 1, p, pl, e, pi + 1, steps)
        elif kind == K_PATH:
            while e < pl and p.unsafe_offset(e)[] != 10:
                e += 1
            return try_ends_t(ops, lits, caps, k, pi, base, nt, ti + 1, p, pl, e, pi, steps)
        elif kind == K_INT:
            while e < pl and is_digit(p.unsafe_offset(e)[]):
                e += 1
            if e == pi:
                return 0
            return try_ends_t(ops, lits, caps, k, pi, base, nt, ti + 1, p, pl, e, pi + 1, steps)
        elif kind == K_FLOAT:
            var d1 = pi
            while d1 < pl and is_digit(p.unsafe_offset(d1)[]):
                d1 += 1
            if d1 == pi:
                return 0
            if d1 + 1 < pl and p.unsafe_offset(d1)[] == 46 and is_digit(
                p.unsafe_offset(d1 + 1)[]
            ):
                var d2 = d1 + 1
                while d2 < pl and is_digit(p.unsafe_offset(d2)[]):
                    d2 += 1
                var r = try_ends_t(ops, lits, caps, k, pi, base, nt, ti + 1, p, pl, d2, d1 + 2, steps)
                if r != 0:
                    return r
            return try_ends_t(ops, lits, caps, k, pi, base, nt, ti + 1, p, pl, d1, pi + 1, steps)
        else:  # K_UUID
            var q = pi
            for k in range(5):
                var n = 12 if k == 4 else (8 if k == 0 else 4)
                if k > 0 and q < pl and p.unsafe_offset(q)[] == 45:
                    q += 1
                for _ in range(n):
                    if q >= pl or not is_hex(p.unsafe_offset(q)[]):
                        return 0
                    q += 1
            caps.unsafe_offset(2 * k)[] = Int32(pi)
            caps.unsafe_offset(2 * k + 1)[] = Int32(q)
            pi = q
            ti += 1
            continue
    if pi == pl or (pi == pl - 1 and p.unsafe_offset(pi)[] == 10):
        return 1
    return 0


def save_caps(t: RouteTable, r: Int):
    var n = 2 * Int(t.pcount[r])
    var src = t.caps.unsafe_ptr()
    var dst = rebind[IPtr](t.bcaps.unsafe_ptr())
    for i in range(n):
        dst.unsafe_offset(i)[] = src.unsafe_offset(i)[]


# 戻り値: 最初に一致したルート番号 / -1=なし / -3=バックトラック上限
def first_match_linear_from(t: RouteTable, p: FPtr, pl: Int, start: Int) -> Int:
    var ops = rebind[IPtr](t.ops.unsafe_ptr())
    var lits = rebind[FPtr](t.lits.unsafe_ptr())
    var caps = rebind[IPtr](t.caps.unsafe_ptr())
    for r in range(start, t.count):
        var base = Int(t.base[r])
        var nt = Int(t.ntok[r])
        var ti = 0
        var pi = 0
        # 先頭がリテラルなら、関数を呼ぶ前にその場で比較して足切りする(続きは2番目のトークンから)
        if nt > 0 and Int(ops.unsafe_offset(base)[]) == LIT:
            var off = Int(ops.unsafe_offset(base + 1)[])
            var ln = Int(ops.unsafe_offset(base + 2)[])
            if pl < ln:
                continue
            var ok = True
            for k in range(ln):
                if lits.unsafe_offset(off + k)[] != p.unsafe_offset(k)[]:
                    ok = False
                    break
            if not ok:
                continue
            ti = 1
            pi = ln
        var steps = 0
        var m = match_t(ops, lits, caps, base, nt, ti, p, pl, pi, steps)
        if m == 1:
            save_caps(t, r)
            return r
        if m == -2:
            return -3
    return -1


# trie版: 経路上のノードに載っている候補だけを、番号の若い順に試す(最小番号を返す=線形版と同じ結果)
def first_match_from(t: RouteTable, p: FPtr, pl: Int, start: Int) -> Int:
    # ルートが少ないうちは線形のほうが速い(実測で10ルート前後が分かれ目)
    if t.count <= LINEAR_MAX:
        return first_match_linear_from(t, p, pl, start)
    var ops = rebind[IPtr](t.ops.unsafe_ptr())
    var lits = rebind[FPtr](t.lits.unsafe_ptr())
    var caps = rebind[IPtr](t.caps.unsafe_ptr())
    var rstart = t.t_rstart.unsafe_ptr()
    var rlen = t.t_rlen.unsafe_ptr()
    var rl = t.rlist.unsafe_ptr()
    var tchild = t.t_child.unsafe_ptr()
    var tnext = t.t_next.unsafe_ptr()
    var tbyte = t.t_byte.unsafe_ptr()
    var rbase = t.base.unsafe_ptr()
    var rntok = t.ntok.unsafe_ptr()
    var best = 1 << 30
    var node = 0
    var pos = 0
    while True:
        var n_here = Int(rlen.unsafe_offset(node)[])
        var st = Int(rstart.unsafe_offset(node)[])
        for q in range(n_here):
            var r = Int(rl.unsafe_offset(st + q)[])
            if r >= best:
                break
            if r < start:
                continue
            var base = Int(rbase.unsafe_offset(r)[])
            var nt = Int(rntok.unsafe_offset(r)[])
            var ti = 0
            if nt > 0 and Int(ops.unsafe_offset(base)[]) == LIT:
                ti = 1  # 先頭リテラルは木をたどる間に照合済み(pos バイト)
            var steps = 0
            var m = match_t(ops, lits, caps, base, nt, ti, p, pl, pos, steps)
            if m == 1:
                best = r
                save_caps(t, r)
                break
            if m == -2:
                return -3
        if pos >= pl:
            break
        var ch = Int(tchild.unsafe_offset(node)[])
        var b = p.unsafe_offset(pos)[]
        while ch >= 0 and tbyte.unsafe_offset(ch)[] != b:
            ch = Int(tnext.unsafe_offset(ch)[])
        if ch < 0:
            break
        node = ch
        pos += 1
    return best if best < (1 << 30) else -1


def first_match(t: RouteTable, p: FPtr, pl: Int) -> Int:
    return first_match_from(t, p, pl, 0)


def first_match_linear(t: RouteTable, p: FPtr, pl: Int) -> Int:
    return first_match_linear_from(t, p, pl, 0)
