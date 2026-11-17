//! 起動時の自動バージョンアップ(標準ライブラリのみ。通信は `curl`、検証は SHA-256)。サーバー単体バイナリ用。
//!
//! 仕組み: 起動のたびに状態ファイルを見て、前回の確認から24時間以上たっていたら、自分自身を隠し引数
//! `--self-update-worker` で切り離して起動し、すぐに本来の処理へ進む(起動は遅くならない)。
//! worker が GitHub の最新リリースを調べ、新しければ資産を取得し、**`<資産名>.sha256` と一致したときだけ**
//! 自分の実行ファイルを入れ替える。次回の起動で一度だけ「更新しました」と表示する。
//! 信頼の根拠は GitHub への TLS と SHA-256(電子署名ではない)。`.sha256` が無いリリースへは更新しない。
//! 止めるには環境変数 `MFASTAPI_NO_UPDATE=1`(CI・`CI` 設定時も自動で止まる)。失敗は黙って次回に回す。

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

pub const REPO: &str = "aon-co-jp/MFastAPI";
pub const CURRENT: &str = env!("CARGO_PKG_VERSION");
const INTERVAL_SECS: u64 = 24 * 3600;
pub const WORKER_ARG: &str = "--self-update-worker";

// ---------- バージョン ----------

pub fn parse_version(s: &str) -> Option<(u64, u64, u64)> {
    let s = s.trim().trim_start_matches('v');
    let core = s.split(['-', '+']).next()?;
    let mut it = core.split('.');
    let v = (it.next()?.parse().ok()?, it.next().unwrap_or("0").parse().ok()?, it.next().unwrap_or("0").parse().ok()?);
    if it.next().is_some() {
        return None;
    }
    Some(v)
}

pub fn is_newer(tag: &str, current: &str) -> bool {
    match (parse_version(tag), parse_version(current)) {
        (Some(a), Some(b)) => a > b && !tag.contains('-'), // 先行版(-alpha 等)へは上げない
        _ => false,
    }
}

// ---------- 資産名 ----------

/// このOS・CPU向けの資産名(無ければ None)。
pub fn asset_name() -> Option<&'static str> {
    if cfg!(target_os = "android") {
        return Some("mfastapi-server-android-aarch64");
    }
    if cfg!(all(target_os = "linux", target_arch = "x86_64")) {
        return Some("mfastapi-server-linux-x86_64");
    }
    if cfg!(all(target_os = "linux", target_arch = "aarch64")) {
        return Some("mfastapi-server-linux-aarch64");
    }
    if cfg!(all(target_os = "macos", target_arch = "x86_64")) {
        return Some("mfastapi-server-macos-x86_64");
    }
    if cfg!(all(target_os = "macos", target_arch = "aarch64")) {
        return Some("mfastapi-server-macos-arm64");
    }
    if cfg!(all(target_os = "windows", target_arch = "x86_64")) {
        return Some("mfastapi-server-windows-x86_64.exe");
    }
    if cfg!(all(target_os = "windows", target_arch = "aarch64")) {
        return Some("mfastapi-server-windows-arm64.exe");
    }
    None
}

/// 取得先は GitHub の公式ホストだけ。
pub fn is_trusted_url(u: &str) -> bool {
    u.starts_with(&format!("https://github.com/{REPO}/releases/download/"))
}

// ---------- SHA-256(標準ライブラリのみ) ----------

pub fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74,
        0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d,
        0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e,
        0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    let mut h: [u32; 8] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&((data.len() as u64) * 8).to_be_bytes());
    for chunk in msg.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([chunk[4 * i], chunk[4 * i + 1], chunk[4 * i + 2], chunk[4 * i + 3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16].wrapping_add(s0).wrapping_add(w[i - 7]).wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ (!e & g);
            let t1 = hh.wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let t2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(t1);
            d = c;
            c = b;
            b = a;
            a = t1.wrapping_add(t2);
        }
        for (x, y) in h.iter_mut().zip([a, b, c, d, e, f, g, hh]) {
            *x = x.wrapping_add(y);
        }
    }
    h.iter().map(|x| format!("{x:08x}")).collect()
}

/// `.sha256` の中身(`<hex>  <name>` または `<hex>`)から先頭のハッシュを取り出す。
pub fn parse_sha256_file(text: &str) -> Option<String> {
    let h = text.split_whitespace().next()?.to_ascii_lowercase();
    (h.len() == 64 && h.bytes().all(|b| b.is_ascii_hexdigit())).then_some(h)
}

// ---------- リリースJSON(RS-JSON方針の対象外: 自分のGitHub応答を文字列として最小限に読む) ----------

/// GitHub の `releases/latest` 応答から (tag_name, [(asset名, ダウンロードURL)]) を取り出す。
pub fn parse_release(json: &str) -> Option<(String, Vec<(String, String)>)> {
    fn field(s: &str, key: &str) -> Option<String> {
        let pat = format!("\"{key}\":\"");
        let i = s.find(&pat)? + pat.len();
        let rest = &s[i..];
        Some(rest[..rest.find('"')?].to_string())
    }
    let compact: String = json.split_whitespace().collect::<Vec<_>>().join("");
    let compact = compact.replace("\":\"", "\":\"");
    let tag = field(&compact, "tag_name")?;
    let mut assets = vec![];
    let mut rest = compact.as_str();
    while let Some(i) = rest.find("\"browser_download_url\":\"") {
        rest = &rest[i..];
        let url = field(rest, "browser_download_url")?;
        let name = url.rsplit('/').next().unwrap_or("").to_string();
        assets.push((name, url));
        rest = &rest["\"browser_download_url\":\"".len()..];
    }
    Some((tag, assets))
}

// ---------- 状態ファイル ----------

fn home() -> Option<PathBuf> {
    std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")).map(PathBuf::from)
}

fn state_dir() -> Option<PathBuf> {
    Some(home()?.join(".mfastapi"))
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

fn read_state(dir: &Path, name: &str) -> Option<String> {
    std::fs::read_to_string(dir.join(name)).ok()
}

pub fn disabled() -> bool {
    std::env::var_os("MFASTAPI_NO_UPDATE").is_some_and(|v| v != "0") || std::env::var_os("CI").is_some()
}

/// 起動時に呼ぶ。更新済みの通知と、必要なら切り離した確認の起動だけを行い、すぐ戻る。
pub fn on_startup(args: &[String]) {
    if disabled() || args.get(1).map(String::as_str) == Some(WORKER_ARG) {
        return;
    }
    let Some(dir) = state_dir() else { return };
    if let Some(v) = read_state(&dir, "updated") {
        eprintln!("mfastapi-server: {} に更新しました(今回の起動から有効)", v.trim());
        let _ = std::fs::remove_file(dir.join("updated"));
    }
    let last: u64 = read_state(&dir, "last_check").and_then(|s| s.trim().parse().ok()).unwrap_or(0);
    if now().saturating_sub(last) < INTERVAL_SECS {
        return;
    }
    let _ = std::fs::create_dir_all(&dir);
    let _ = std::fs::write(dir.join("last_check"), now().to_string()); // 先に記録(失敗しても連打しない)
    let Ok(exe) = std::env::current_exe() else { return };
    let mut cmd = Command::new(exe);
    cmd.arg(WORKER_ARG).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0000_0008 | 0x0800_0000); // DETACHED_PROCESS | CREATE_NO_WINDOW
    }
    let _ = cmd.spawn();
}

// ---------- worker ----------

fn curl(args: &[&str]) -> Option<Vec<u8>> {
    let out = Command::new("curl").args(["-fsSL", "--max-time", "120", "-A", "mfastapi-updater"]).args(args).output().ok()?;
    out.status.success().then_some(out.stdout)
}

/// worker 本体。更新したら新しい版名を返す。
pub fn run_worker() -> Result<Option<String>, String> {
    if disabled() {
        return Ok(None);
    }
    let body = curl(&[&format!("https://api.github.com/repos/{REPO}/releases/latest")]).ok_or("リリース情報を取得できない")?;
    let (tag, assets) = parse_release(&String::from_utf8_lossy(&body)).ok_or("リリース情報を読めない")?;
    if !is_newer(&tag, CURRENT) {
        return Ok(None);
    }
    let name = asset_name().ok_or("このOS向けの資産が無い")?;
    let find = |n: &str| assets.iter().find(|(a, _)| a == n).map(|(_, u)| u.clone());
    let url = find(name).ok_or("資産が見つからない")?;
    let sha_url = find(&format!("{name}.sha256")).ok_or("`.sha256` が無いリリースへは更新しない")?;
    if !is_trusted_url(&url) || !is_trusted_url(&sha_url) {
        return Err("信頼できない取得先".into());
    }
    let want = parse_sha256_file(&String::from_utf8_lossy(&curl(&[&sha_url]).ok_or("sha256 を取得できない")?)).ok_or("sha256 を読めない")?;
    let bytes = curl(&[&url]).ok_or("資産を取得できない")?;
    let got = sha256_hex(&bytes);
    if got != want {
        return Err(format!("sha256 不一致(期待 {want}、実際 {got})"));
    }
    let tmp = std::env::temp_dir().join(format!("mfastapi-update-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&tmp);
    std::fs::create_dir_all(&tmp).map_err(|e| e.to_string())?;
    let file = tmp.join(name);
    std::fs::write(&file, &bytes).map_err(|e| e.to_string())?;
    let res = apply(&file, &tmp);
    let _ = std::fs::remove_dir_all(&tmp);
    res?;
    if let Some(dir) = state_dir() {
        let _ = std::fs::write(dir.join("updated"), tag.trim_start_matches('v'));
    }
    Ok(Some(tag))
}

/// 実行ファイルを入れ替える。同じ場所に新しい名前で置いてから rename(中途半端な状態を残さない)。
/// Windows は実行中の exe を rename で脇へ退避できる(上書きはできない)。
fn apply(new_file: &Path, _tmp: &Path) -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let staged = exe.with_extension("new");
    std::fs::copy(new_file, &staged).map_err(|e| format!("書き込めない({}): {e}", staged.display()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&staged, std::fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
    }
    #[cfg(windows)]
    {
        let old = exe.with_extension("old");
        let _ = std::fs::remove_file(&old);
        std::fs::rename(&exe, &old).map_err(|e| {
            let _ = std::fs::remove_file(&staged);
            e.to_string()
        })?;
        if let Err(e) = std::fs::rename(&staged, &exe) {
            let _ = std::fs::rename(&old, &exe); // 戻す
            return Err(e.to_string());
        }
        return Ok(());
    }
    #[cfg(not(windows))]
    std::fs::rename(&staged, &exe).map_err(|e| {
        let _ = std::fs::remove_file(&staged);
        e.to_string()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_known_vectors() {
        assert_eq!(sha256_hex(b""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        assert_eq!(sha256_hex(b"abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        let long = vec![b'a'; 1000];
        assert_eq!(sha256_hex(&long), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3");
    }

    #[test]
    fn version_order_and_prerelease() {
        assert!(is_newer("v0.4.3", "0.4.2"));
        assert!(is_newer("0.10.0", "0.9.9"));
        assert!(!is_newer("v0.4.2", "0.4.2"));
        assert!(!is_newer("v0.4.1", "0.4.2"));
        assert!(!is_newer("v0.5.0-alpha", "0.4.2"));
        assert!(!is_newer("garbage", "0.4.2"));
    }

    #[test]
    fn parses_release_json_and_picks_assets() {
        let j = r#"{"tag_name": "v0.4.3", "assets": [
          {"name": "a", "browser_download_url": "https://github.com/aon-co-jp/MFastAPI/releases/download/v0.4.3/a"},
          {"name": "a.sha256", "browser_download_url": "https://github.com/aon-co-jp/MFastAPI/releases/download/v0.4.3/a.sha256"}]}"#;
        let (tag, assets) = parse_release(j).unwrap();
        assert_eq!(tag, "v0.4.3");
        assert_eq!(assets.len(), 2);
        assert_eq!(assets[1].0, "a.sha256");
        assert!(assets.iter().all(|(_, u)| is_trusted_url(u)));
    }

    #[test]
    fn rejects_untrusted_hosts() {
        assert!(!is_trusted_url("https://evil.example/aon-co-jp/MFastAPI/releases/download/v1/x"));
        assert!(!is_trusted_url("https://github.com/other/MFastAPI/releases/download/v1/x"));
        assert!(!is_trusted_url("http://github.com/aon-co-jp/MFastAPI/releases/download/v1/x"));
    }

    #[test]
    fn sha256_file_formats() {
        let h = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
        assert_eq!(parse_sha256_file(&format!("{h}  file.tar.gz\n")).as_deref(), Some(h));
        assert_eq!(parse_sha256_file(h).as_deref(), Some(h));
        assert!(parse_sha256_file("zz").is_none());
        assert!(parse_sha256_file("").is_none());
    }

    #[test]
    fn this_platform_has_an_asset() {
        assert!(asset_name().is_some());
    }
}
