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
}
