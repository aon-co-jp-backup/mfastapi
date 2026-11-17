//! Demo server with the same routes as the Mojo stage-C / stage-B servers (and the FastAPI reference app in tests/mojo_endpoint).
//! Usage: mfastapi-server c <port>                       (pure Rust handlers)
//!        mfastapi-server b <port> <dir-with-pyhandlers>  (needs --features python)
use mfastapi_server::{server, App, Args, Kind, Method, Param, Resp, Route};

fn fib(n: i64) -> i64 {
    if n < 2 {
        n
    } else {
        fib(n - 1) + fib(n - 2)
    }
}

fn count_primes(limit: usize) -> usize {
    if limit < 2 {
        return 0;
    }
    let mut sieve = vec![true; limit + 1];
    sieve[0] = false;
    sieve[1] = false;
    let mut i = 2;
    while i * i <= limit {
        if sieve[i] {
            let mut j = i * i;
            while j <= limit {
                sieve[j] = false;
                j += i;
            }
        }
        i += 1;
    }
    sieve.iter().filter(|&&b| b).count()
}

fn words(s: &str) -> usize {
    s.split(|c: char| c == ' ' || c == '\n' || c == '\t' || c == '\r').filter(|w| !w.is_empty()).count()
}

fn rust_fib(max: i64) -> impl Fn(&Args) -> Resp + Send + Sync {
    move |a| {
        let n = a.int("n");
        if n < 0 || n > max {
            return Resp::detail(400, &format!("n must be between 0 and {max}"));
        }
        Resp::json(200, fib(n).to_string())
    }
}

fn routes_c() -> Vec<Route> {
    vec![
        Route { method: Method::Get, body: false, path: "/fib/{n}", name: "fib", params: vec![Param::path("n", Kind::Int)], returns: Kind::Int, handler: Box::new(rust_fib(45)) },
        Route {
            method: Method::Get,
            body: false,
            path: "/primes",
            name: "primes",
            params: vec![Param::query("n", Kind::Int).default_int(1000)],
            returns: Kind::Int,
            handler: Box::new(|a| {
                let n = a.int("n");
                if !(0..=100_000_000).contains(&n) {
                    return Resp::detail(400, "n must be between 0 and 100000000");
                }
                Resp::json(200, count_primes(n as usize).to_string())
            }),
        },
        Route {
            method: Method::Get,
            body: false,
            path: "/words",
            name: "words",
            params: vec![Param::query("text", Kind::Str)],
            returns: Kind::Int,
            handler: Box::new(|a| Resp::json(200, words(a.str("text")).to_string())),
        },
        Route {
            method: Method::Post,
            body: true,
            path: "/echo",
            name: "echo",
            params: vec![],
            returns: Kind::Str,
            handler: Box::new(|a| Resp::json(200, a.json().map(|v| v.to_string()).unwrap_or_default())),
        },
        Route {
            method: Method::Delete,
            body: false,
            path: "/echo",
            name: "echo_delete",
            params: vec![],
            returns: Kind::Str,
            handler: Box::new(|_| Resp::json(200, "{\"deleted\":true}".into())),
        },
    ]
}

#[cfg(feature = "python")]
fn routes_b() -> Vec<Route> {
    use mfastapi_server::pybridge::call;
    vec![
        Route {
            method: Method::Get,
            body: false,
            path: "/py/hello/{name}",
            name: "py_hello",
            params: vec![Param::path("name", Kind::Str)],
            returns: Kind::Str,
            handler: Box::new(|a| call("greet", a.str("name"))),
        },
        Route {
            method: Method::Get,
            body: false,
            path: "/py/fib/{n}",
            name: "py_fib",
            params: vec![Param::path("n", Kind::Int)],
            returns: Kind::Int,
            handler: Box::new(|a| {
                let n = a.int("n");
                if !(0..=35).contains(&n) {
                    return Resp::detail(400, "n must be between 0 and 35");
                }
                call("fib", &n.to_string())
            }),
        },
        Route {
            method: Method::Get,
            body: false,
            path: "/py/stats",
            name: "py_stats",
            params: vec![Param::query("csv", Kind::Str)],
            returns: Kind::Str,
            handler: Box::new(|a| call("stats", a.str("csv"))),
        },
        Route { method: Method::Get, body: false, path: "/fib/{n}", name: "fib", params: vec![Param::path("n", Kind::Int)], returns: Kind::Int, handler: Box::new(rust_fib(45)) },
    ]
}

fn main() -> std::io::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("--cpu") {
        print!("{}", mfastapi_server::cpu::report());
        return Ok(());
    }
    // ワーカースレッド数は open-cpu のコア構成から決める(MFASTAPI_THREADS で上書き可)
    tokio::runtime::Builder::new_multi_thread().worker_threads(mfastapi_server::cpu::worker_threads()).enable_all().build()?.block_on(serve(args))
}

async fn serve(args: Vec<String>) -> std::io::Result<()> {
    let mode = args.get(1).map(String::as_str).unwrap_or("c");
    let port = args.get(2).map(String::as_str).unwrap_or("8080");
    let routes = match mode {
        "c" => routes_c(),
        #[cfg(feature = "python")]
        "b" => {
            if let Some(dir) = args.get(3) {
                mfastapi_server::pybridge::add_path(dir);
            }
            routes_b()
        }
        _ => {
            eprintln!("usage: mfastapi-server c <port> | b <port> <pydir> (b needs --features python)");
            std::process::exit(2);
        }
    };
    let app = App::new(routes).expect("routes");
    println!("mfastapi-server ({mode}) listening on 127.0.0.1:{port}");
    server::run(app, &format!("127.0.0.1:{port}")).await
}
