//! Starlette-compatible path matching and the compiled route table, in safe Rust (port of c/fastapim_cabi.c).
//! Semantics follow Starlette's compile_path()/re.match:
//!   {name} {name:str} -> [^/]+   {name:path} -> .*   {name:int} -> [0-9]+   {name:float} -> [0-9]+(\.[0-9]+)?
//!   {name:uuid} -> 8-4-4-4-12 hex with optional '-'. A '{' that is not a valid {name[:type]} is a literal.
//! Return codes: 1 match, 0 no match, -1 unknown convertor type, -2 backtracking budget exhausted.
//! The matcher indexes only into slices it was given (bounds-checked), recursion depth is bounded by the template length.

const BUDGET: i64 = 200_000;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    Str,
    Path,
    Int,
    Float,
    Uuid,
}

fn is_alpha(c: u8) -> bool {
    c.is_ascii_alphabetic() || c == b'_'
}
fn is_alnum(c: u8) -> bool {
    is_alpha(c) || c.is_ascii_digit()
}

/// `t[i] == '{'`: Ok(Some((next, kind))) valid param, Ok(None) literal brace, Err(()) unknown convertor type.
fn parse_param(t: &[u8], i: usize) -> Result<Option<(usize, Kind)>, ()> {
    let mut j = i + 1;
    if j >= t.len() || !is_alpha(t[j]) {
        return Ok(None);
    }
    while j < t.len() && is_alnum(t[j]) {
        j += 1;
    }
    if j < t.len() && t[j] == b':' {
        let s = j + 1;
        let mut e = s;
        if e >= t.len() || !is_alpha(t[e]) {
            return Ok(None);
        }
        while e < t.len() && is_alnum(t[e]) {
            e += 1;
        }
        if e >= t.len() || t[e] != b'}' {
            return Ok(None);
        }
        let kind = match &t[s..e] {
            b"str" => Kind::Str,
            b"path" => Kind::Path,
            b"int" => Kind::Int,
            b"float" => Kind::Float,
            b"uuid" => Kind::Uuid,
            _ => return Err(()),
        };
        return Ok(Some((e + 1, kind)));
    }
    if j >= t.len() || t[j] != b'}' {
        return Ok(None);
    }
    Ok(Some((j + 1, Kind::Str)))
}

struct Ctx<'a> {
    t: &'a [u8],
    p: &'a [u8],
    steps: i64,
}

impl<'a> Ctx<'a> {
    fn try_ends(&mut self, ti: usize, hi: usize, lo: usize) -> i32 {
        let mut e = hi as i64;
        while e >= lo as i64 {
            let eu = e as usize;
            // never split inside a UTF-8 character (Python's re works on code points)
            if eu < self.p.len() && (self.p[eu] & 0xC0) == 0x80 {
                e -= 1;
                continue;
            }
            self.steps += 1;
            if self.steps > BUDGET {
                return -2;
            }
            let r = self.match_from(ti, eu);
            if r != 0 {
                return r;
            }
            e -= 1;
        }
        0
    }

    fn match_from(&mut self, mut ti: usize, mut pi: usize) -> i32 {
        let (t, p) = (self.t, self.p);
        while ti < t.len() {
            let ch = t[ti];
            if ch == b'{' {
                match parse_param(t, ti) {
                    Err(()) => return -1,
                    Ok(Some((nx, kind))) => match kind {
                        Kind::Str => {
                            let mut e = pi;
                            while e < p.len() && p[e] != b'/' {
                                e += 1;
                            }
                            return if e > pi { self.try_ends(nx, e, pi + 1) } else { 0 };
                        }
                        Kind::Path => {
                            let mut e = pi;
                            while e < p.len() && p[e] != b'\n' {
                                e += 1;
                            }
                            return self.try_ends(nx, e, pi);
                        }
                        Kind::Int => {
                            let mut e = pi;
                            while e < p.len() && p[e].is_ascii_digit() {
                                e += 1;
                            }
                            return if e > pi { self.try_ends(nx, e, pi + 1) } else { 0 };
                        }
                        Kind::Float => {
                            let mut d1 = pi;
                            while d1 < p.len() && p[d1].is_ascii_digit() {
                                d1 += 1;
                            }
                            if d1 == pi {
                                return 0;
                            }
                            if d1 + 1 < p.len() && p[d1] == b'.' && p[d1 + 1].is_ascii_digit() {
                                let mut d2 = d1 + 1;
                                while d2 < p.len() && p[d2].is_ascii_digit() {
                                    d2 += 1;
                                }
                                let r = self.try_ends(nx, d2, d1 + 2);
                                if r != 0 {
                                    return r;
                                }
                            }
                            return self.try_ends(nx, d1, pi + 1);
                        }
                        Kind::Uuid => {
                            const G: [usize; 5] = [8, 4, 4, 4, 12];
                            let mut q = pi;
                            for (k, &g) in G.iter().enumerate() {
                                if k > 0 && q < p.len() && p[q] == b'-' {
                                    q += 1;
                                }
                                for _ in 0..g {
                                    if q >= p.len() || !p[q].is_ascii_hexdigit() {
                                        return 0;
                                    }
                                    q += 1;
                                }
                            }
                            pi = q;
                            ti = nx;
                            continue;
                        }
                    },
                    Ok(None) => {}
                }
            }
            if pi >= p.len() || p[pi] != ch {
                return 0;
            }
            ti += 1;
            pi += 1;
        }
        // '$': end of path, or one trailing '\n'
        if pi == p.len() || (pi + 1 == p.len() && p[pi] == b'\n') {
            1
        } else {
            0
        }
    }
}

/// Does `path` match the Starlette path template `tpl`?
pub fn path_matches(tpl: &[u8], path: &[u8]) -> i32 {
    Ctx { t: tpl, p: path, steps: 0 }.match_from(0, 0)
}

/// First matching template among '\n'-separated `tpls`: index, -1 none, -2 bad convertor type, -3 gave up.
pub fn route_first_match(tpls: &[u8], path: &[u8]) -> i32 {
    for (idx, tpl) in tpls.split(|&b| b == b'\n').enumerate() {
        match path_matches(tpl, path) {
            1 => return idx as i32,
            -1 => return -2,
            -2 => return -3,
            _ => {}
        }
    }
    -1
}

struct Route {
    tpl: Vec<u8>,
    lead: usize,
    next: i32,
}

#[derive(Clone)]
struct Node {
    child: i32,
    sib: i32,
    head: i32,
    tail: i32,
    byte: u8,
}

/// Compiled route table: a byte trie over each template's leading literal; routes in one trie node are chained in ascending order.
pub struct Table {
    routes: Vec<Route>,
    nodes: Vec<Node>,
}

impl Default for Table {
    fn default() -> Self {
        Self::new()
    }
}

impl Table {
    pub fn new() -> Self {
        Table { routes: Vec::new(), nodes: vec![Node { child: -1, sib: -1, head: -1, tail: -1, byte: 0 }] }
    }

    pub fn len(&self) -> usize {
        self.routes.len()
    }

    pub fn is_empty(&self) -> bool {
        self.routes.is_empty()
    }

    /// Ok on success, Err(-1) for an unknown convertor type.
    pub fn add(&mut self, tpl: &[u8]) -> Result<(), i32> {
        let mut lead: Option<usize> = None;
        let mut i = 0;
        while i < tpl.len() {
            if tpl[i] == b'{' {
                match parse_param(tpl, i) {
                    Err(()) => return Err(-1),
                    Ok(Some((nx, _))) => {
                        if lead.is_none() {
                            lead = Some(i);
                        }
                        i = nx;
                        continue;
                    }
                    Ok(None) => {}
                }
            }
            i += 1;
        }
        let lead = lead.unwrap_or(tpl.len());
        let idx = self.routes.len() as i32;
        let mut node = 0usize;
        for &b in &tpl[..lead] {
            let mut ch = self.nodes[node].child;
            while ch >= 0 && self.nodes[ch as usize].byte != b {
                ch = self.nodes[ch as usize].sib;
            }
            if ch < 0 {
                self.nodes.push(Node { child: -1, sib: self.nodes[node].child, head: -1, tail: -1, byte: b });
                ch = self.nodes.len() as i32 - 1;
                self.nodes[node].child = ch;
            }
            node = ch as usize;
        }
        self.routes.push(Route { tpl: tpl.to_vec(), lead, next: -1 });
        let tail = self.nodes[node].tail;
        if tail >= 0 {
            self.routes[tail as usize].next = idx;
        } else {
            self.nodes[node].head = idx;
        }
        self.nodes[node].tail = idx;
        Ok(())
    }

    /// Smallest route index >= start that matches; -1 none; -3 backtracking budget exhausted.
    pub fn first_match_from(&self, path: &[u8], start: i32) -> i32 {
        let start = start.max(0);
        let mut node = 0usize;
        let mut best = i32::MAX;
        let mut pos = 0usize;
        loop {
            let mut k = self.nodes[node].head;
            while k >= 0 && k < best {
                if k >= start {
                    let r = &self.routes[k as usize];
                    let mut c = Ctx { t: &r.tpl, p: path, steps: 0 };
                    match c.match_from(r.lead, r.lead) {
                        1 => {
                            best = k;
                            break;
                        }
                        -2 => return -3,
                        _ => {}
                    }
                }
                k = self.routes[k as usize].next;
            }
            if pos >= path.len() {
                break;
            }
            let mut ch = self.nodes[node].child;
            while ch >= 0 && self.nodes[ch as usize].byte != path[pos] {
                ch = self.nodes[ch as usize].sib;
            }
            if ch < 0 {
                break;
            }
            node = ch as usize;
            pos += 1;
        }
        if best == i32::MAX {
            -1
        } else {
            best
        }
    }
}
