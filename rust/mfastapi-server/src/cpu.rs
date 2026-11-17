//! CPU構成の利用(open-cpu)。big.LITTLE機ではワーカースレッドを高性能コアの数に合わせる。
//!
//! 効率コア(Cortex-A5x/A3x/A510系など)は、リクエスト処理のtail latencyを悪化させるため数えない。
//! 判定できない場合(x86、コア名が取れない環境)は `available_parallelism` をそのまま使う。

/// コア名から効率コアかを判定する(未知の名前は高性能として扱う)。
pub fn is_efficiency_core(name: &str) -> bool {
    let n = name.to_ascii_lowercase();
    ["a34", "a35", "a53", "a55", "a65", "a510", "a520", "a525", "x1e-eff"].iter().any(|k| n.contains(k))
}

/// 高性能コア数(0にはならない)。`groups` は (コア名, 個数)。
pub fn performance_cores(groups: &[(String, usize)], fallback: usize) -> usize {
    if groups.is_empty() {
        return fallback.max(1);
    }
    let perf: usize = groups.iter().filter(|(n, _)| !is_efficiency_core(n)).map(|(_, c)| *c).sum();
    if perf == 0 {
        fallback.max(1)
    } else {
        perf
    }
}

/// 使うワーカースレッド数。`MFASTAPI_THREADS` があればそれを優先する。
pub fn worker_threads() -> usize {
    if let Some(n) = std::env::var("MFASTAPI_THREADS").ok().and_then(|v| v.parse::<usize>().ok()).filter(|n| *n > 0) {
        return n;
    }
    let all = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1);
    let groups: Vec<(String, usize)> = open_cpu::inventory().cores.iter().map(|g| (g.name.clone(), g.count)).collect();
    performance_cores(&groups, all).min(all).max(1)
}

/// `--cpu` で表示する、検出した命令セットとコア構成。
pub fn report() -> String {
    format!("{}worker threads: {}\n", open_cpu::inventory().summary(), worker_threads())
}

/// この長さ(バイト)以上のクエリ文字列だけ、SIMDの区切り探索を使う(短い入力では分岐コストの方が大きい)。
pub const SIMD_QUERY_MIN: usize = 256;

/// `mfastapi_core::query_last` と同じ結果を返す。長いクエリ文字列では `&` と `=` の探索を
/// open-cpu の `find_byte`(AVX-512BW > AVX2 > NEON > スカラーを自動選択)で行う。
pub fn query_last(query: &[u8], name: &[u8]) -> Option<Vec<u8>> {
    if query.len() < SIMD_QUERY_MIN || query.len() > mfastapi_core::MAX_INPUT {
        return mfastapi_core::query_last(query, name);
    }
    let mut found = None;
    let mut rest = query;
    loop {
        let (pair, next) = match open_cpu::find_byte(rest, b'&') {
            Some(p) => (&rest[..p], Some(&rest[p + 1..])),
            None => (rest, None),
        };
        if !pair.is_empty() {
            let (k, v) = match open_cpu::find_byte(pair, b'=') {
                Some(p) => (&pair[..p], &pair[p + 1..]),
                None => (pair, &pair[0..0]),
            };
            if mfastapi_core::query_decode(k) == name {
                found = Some(mfastapi_core::query_decode(v));
            }
        }
        match next {
            Some(n) => rest = n,
            None => return found,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn efficiency_cores_are_recognised() {
        assert!(is_efficiency_core("Cortex-A55"));
        assert!(is_efficiency_core("Cortex-A510"));
        assert!(!is_efficiency_core("Cortex-A78"));
        assert!(!is_efficiency_core("Cortex-X3"));
    }

    #[test]
    fn performance_core_count() {
        let g = vec![("Cortex-A78".to_string(), 4), ("Cortex-A55".to_string(), 4)];
        assert_eq!(performance_cores(&g, 8), 4);
        assert_eq!(performance_cores(&[], 6), 6);
        let only_little = vec![("Cortex-A53".to_string(), 8)];
        assert_eq!(performance_cores(&only_little, 8), 8);
    }

    #[test]
    fn query_last_matches_core_on_random_queries() {
        let mut s = 0x9E3779B97F4A7C15u64;
        let mut next = || {
            s ^= s << 13;
            s ^= s >> 7;
            s ^= s << 17;
            s
        };
        let alphabet = b"ab&=%+2F0 xyz";
        for round in 0..400 {
            let len = (next() % 3000) as usize + if round % 2 == 0 { 256 } else { 0 };
            let q: Vec<u8> = (0..len).map(|_| alphabet[(next() % alphabet.len() as u64) as usize]).collect();
            for name in [&b"a"[..], b"b", b"ab", b"x y", b"z", b""] {
                assert_eq!(query_last(&q, name), mfastapi_core::query_last(&q, name), "round={round} name={:?}", name);
            }
        }
    }

    #[test]
    fn query_last_edge_cases() {
        let mut q = b"a=1&a=2&".to_vec();
        q.extend(std::iter::repeat(b'x').take(300));
        assert_eq!(query_last(&q, b"a"), Some(b"2".to_vec()));
        assert_eq!(query_last(&q, b"x"), mfastapi_core::query_last(&q, b"x"));
    }
}
