//! MFastAPI security core. All parsing is safe Rust (`forbid(unsafe_code)` for the crate root); the only `unsafe` is the C-ABI shim in `ffi`.
//! Hard limits: input length is capped (`MAX_INPUT`), integers are bounded to i64, output buffers are caller-sized.
#![deny(unsafe_code)]

pub mod matcher;

pub const MAX_INPUT: usize = 1 << 20; // 1 MiB per value

#[derive(Debug, PartialEq, Eq)]
pub enum IntError {
    Invalid,
    OutOfRange,
    TooLong,
}

fn is_ws(b: u8) -> bool {
    b == b' ' || (9..=13).contains(&b)
}

/// Pydantic lax-mode int from str: surrounding ASCII whitespace, optional sign, digits with single `_` between digits,
/// optional `.000` fraction (zeros only). Values outside i64 -> `OutOfRange` (Pydantic accepts big ints; MFastAPI bounds them).
pub fn parse_int(s: &[u8]) -> Result<i64, IntError> {
    if s.len() > MAX_INPUT {
        return Err(IntError::TooLong);
    }
    let mut lo = 0;
    let mut hi = s.len();
    while lo < hi && is_ws(s[lo]) {
        lo += 1;
    }
    while hi > lo && is_ws(s[hi - 1]) {
        hi -= 1;
    }
    let s = &s[lo..hi];
    if s.is_empty() {
        return Err(IntError::Invalid);
    }
    let (neg, mut i) = match s[0] {
        b'+' => (false, 1),
        b'-' => (true, 1),
        _ => (false, 0),
    };
    let mut v: i128 = 0;
    let mut seen = false;
    let mut prev_us = false;
    while i < s.len() {
        match s[i] {
            c @ b'0'..=b'9' => {
                v = v * 10 + i128::from(c - b'0');
                if v > (1i128 << 64) {
                    return Err(IntError::OutOfRange);
                }
                seen = true;
                prev_us = false;
            }
            b'_' if seen && (!prev_us || (v == 0 && i + 1 < s.len())) => prev_us = true,
            _ => break,
        }
        i += 1;
    }
    if !seen || prev_us {
        // Pydantic quirk: a zero run (underscores allowed) directly followed by "-<number>" parses as the negative number
        // ("0-5" -> -5, "0_-5" -> -5; the number must not have a leading zero unless it is exactly "0").
        if seen && s[0] != b'-' && v == 0 && i < s.len() && s[i] == b'-' {
            return quirk_negative(&s[i + 1..]);
        }
        return Err(IntError::Invalid);
    }
    if seen && !prev_us && s[0] != b'-' && v == 0 && i < s.len() && s[i] == b'-' {
        return quirk_negative(&s[i + 1..]);
    }
    if i < s.len() && (s[i] != b'.' || i + 1 >= s.len() || s[i + 1..].iter().any(|&b| b != b'0')) {
        return Err(IntError::Invalid);
    }
    let v = if neg { -v } else { v };
    i64::try_from(v).map_err(|_| IntError::OutOfRange)
}

fn quirk_negative(rest: &[u8]) -> Result<i64, IntError> {
    let rest = if rest.first() == Some(&b'_') { &rest[1..] } else { rest };
    if rest.is_empty() || !rest[0].is_ascii_digit() || (rest[0] == b'0' && rest.len() > 1 && rest[1] != b'.') {
        return Err(IntError::Invalid);
    }
    match parse_int(rest) {
        Ok(v) => v.checked_neg().ok_or(IntError::OutOfRange),
        Err(e) => Err(e),
    }
}

fn hex(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

/// application/x-www-form-urlencoded style decode (`+` -> space, `%XX` -> byte; malformed `%` kept literally), then UTF-8 lossy.
pub fn query_decode(s: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        match s[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < s.len() && hex(s[i + 1]).is_some() && hex(s[i + 2]).is_some() => {
                out.push(hex(s[i + 1]).unwrap_or(0) * 16 + hex(s[i + 2]).unwrap_or(0));
                i += 2;
            }
            c => out.push(c),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned().into_bytes()
}

/// Last value of `name` in a raw query string (Starlette/parse_qsl keep_blank_values semantics: duplicates -> last wins, bare key -> "").
pub fn query_last(query: &[u8], name: &[u8]) -> Option<Vec<u8>> {
    if query.len() > MAX_INPUT {
        return None;
    }
    let mut found = None;
    for pair in query.split(|&b| b == b'&') {
        if pair.is_empty() {
            continue;
        }
        let (k, v) = match pair.iter().position(|&b| b == b'=') {
            Some(p) => (&pair[..p], &pair[p + 1..]),
            None => (pair, &pair[0..0]),
        };
        if query_decode(k) == name {
            found = Some(query_decode(v));
        }
    }
    found
}

pub mod ffi {
    //! C ABI. Every pointer/length pair is validated; panics abort (panic = "abort") rather than unwinding across the boundary.
    #![allow(unsafe_code)]
    use super::*;

    unsafe fn slice<'a>(p: *const u8, n: i64) -> Option<&'a [u8]> {
        if n < 0 {
            return None;
        }
        if n == 0 {
            return Some(&[]);
        }
        if p.is_null() {
            return None;
        }
        Some(std::slice::from_raw_parts(p, n as usize))
    }

    // ---- same C ABI as c/mfastapi_cabi.c, so the ctypes loader (python/mfastapi/native.py) works unchanged ----
    #[no_mangle]
    pub extern "C" fn mfastapi_abi_version() -> i32 {
        1
    }

    #[no_mangle]
    pub extern "C" fn mfastapi_add(a: i64, b: i64) -> i64 {
        a.wrapping_add(b)
    }

    #[no_mangle]
    pub unsafe extern "C" fn mfastapi_path_matches(tpl: *const u8, tl: i64, path: *const u8, pl: i64) -> i32 {
        match (slice(tpl, tl), slice(path, pl)) {
            (Some(t), Some(p)) => matcher::path_matches(t, p),
            _ => 0,
        }
    }

    #[no_mangle]
    pub unsafe extern "C" fn mfastapi_route_first_match(tpls: *const u8, tl: i64, path: *const u8, pl: i64) -> i32 {
        match (slice(tpls, tl), slice(path, pl)) {
            (Some(t), Some(p)) => matcher::route_first_match(t, p),
            _ => -1,
        }
    }

    #[no_mangle]
    pub extern "C" fn mfastapi_table_new() -> *mut matcher::Table {
        Box::into_raw(Box::new(matcher::Table::new()))
    }

    #[no_mangle]
    pub unsafe extern "C" fn mfastapi_table_free(h: *mut matcher::Table) {
        if !h.is_null() {
            drop(Box::from_raw(h));
        }
    }

    #[no_mangle]
    pub unsafe extern "C" fn mfastapi_table_size(h: *mut matcher::Table) -> i32 {
        if h.is_null() {
            0
        } else {
            (*h).len() as i32
        }
    }

    /// 0 ok, -1 unknown convertor type, -2 bad arguments.
    #[no_mangle]
    pub unsafe extern "C" fn mfastapi_table_add(h: *mut matcher::Table, tpl: *const u8, tl: i64) -> i32 {
        let (Some(t), false) = (slice(tpl, tl), h.is_null()) else { return -2 };
        match (*h).add(t) {
            Ok(()) => 0,
            Err(c) => c,
        }
    }

    #[no_mangle]
    pub unsafe extern "C" fn mfastapi_table_first_match_from(h: *mut matcher::Table, path: *const u8, pl: i64, start: i32) -> i32 {
        let (Some(p), false) = (slice(path, pl), h.is_null()) else { return -1 };
        (*h).first_match_from(p, start)
    }

    #[no_mangle]
    pub extern "C" fn mfastapi_rs_abi_version() -> i32 {
        1
    }

    /// 0 ok (value in *out), 1 invalid, 2 out of range, 3 too long, -1 bad arguments.
    #[no_mangle]
    pub unsafe extern "C" fn mfastapi_rs_parse_int(p: *const u8, n: i64, out: *mut i64) -> i32 {
        if out.is_null() {
            return -1;
        }
        let Some(s) = slice(p, n) else { return -1 };
        match parse_int(s) {
            Ok(v) => {
                *out = v;
                0
            }
            Err(IntError::Invalid) => 1,
            Err(IntError::OutOfRange) => 2,
            Err(IntError::TooLong) => 3,
        }
    }

    /// Writes the decoded last value into buf[..cap]. Returns its length, -1 not found, -2 buffer too small, -3 bad arguments.
    #[no_mangle]
    pub unsafe extern "C" fn mfastapi_rs_query_last(
        q: *const u8,
        ql: i64,
        name: *const u8,
        nl: i64,
        buf: *mut u8,
        cap: i64,
    ) -> i64 {
        let (Some(q), Some(name)) = (slice(q, ql), slice(name, nl)) else { return -3 };
        if cap < 0 || (cap > 0 && buf.is_null()) {
            return -3;
        }
        match query_last(q, name) {
            None => -1,
            Some(v) if v.len() as i64 > cap => -2,
            Some(v) => {
                if !v.is_empty() {
                    std::ptr::copy_nonoverlapping(v.as_ptr(), buf, v.len());
                }
                v.len() as i64
            }
        }
    }

    /// Length of the decoded last value (for sizing the buffer), -1 if absent, -3 bad arguments.
    #[no_mangle]
    pub unsafe extern "C" fn mfastapi_rs_query_last_len(q: *const u8, ql: i64, name: *const u8, nl: i64) -> i64 {
        let (Some(q), Some(name)) = (slice(q, ql), slice(name, nl)) else { return -3 };
        query_last(q, name).map_or(-1, |v| v.len() as i64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ints() {
        assert_eq!(parse_int(b" 5 "), Ok(5));
        assert_eq!(parse_int(b"1_000.0"), Ok(1000));
        assert_eq!(parse_int(b"1__0"), Err(IntError::Invalid));
        assert_eq!(parse_int(b"5."), Err(IntError::Invalid));
        assert_eq!(parse_int(b"9223372036854775808"), Err(IntError::OutOfRange));
        assert_eq!(parse_int(b"-9223372036854775808"), Ok(i64::MIN));
    }

    #[test]
    fn query() {
        assert_eq!(query_last(b"n=5&n=7", b"n"), Some(b"7".to_vec()));
        assert_eq!(query_last(b"n", b"n"), Some(Vec::new()));
        assert_eq!(query_last(b"a=b+c", b"a"), Some(b"b c".to_vec()));
    }
}
