//! hyper/tokio HTTP/1.1 front end for `App`. Handlers run on the blocking pool so CPU-heavy handlers never stall the reactor.
use crate::{App, Resp};
use bytes::Bytes;
use http_body_util::Full;
use hyper::{body::Incoming, service::service_fn, Method, Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use std::sync::Arc;
use tokio::net::TcpListener;

fn to_response(r: Resp) -> Response<Full<Bytes>> {
    Response::builder()
        .status(StatusCode::from_u16(r.status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR))
        .header("content-type", r.ctype)
        .body(Full::new(Bytes::from(r.body)))
        .unwrap_or_else(|_| Response::new(Full::new(Bytes::new())))
}

async fn serve_one(app: Arc<App>, req: Request<Incoming>) -> Result<Response<Full<Bytes>>, std::convert::Infallible> {
    if req.method() != Method::GET {
        return Ok(to_response(Resp::detail(405, "Method Not Allowed")));
    }
    let path = req.uri().path().to_string();
    let query = req.uri().query().unwrap_or("").to_string();
    let r = tokio::task::spawn_blocking(move || app.handle(&path, &query))
        .await
        .unwrap_or_else(|_| Resp::detail(500, "Internal Server Error"));
    Ok(to_response(r))
}

pub async fn run(app: App, addr: &str) -> std::io::Result<()> {
    let app = Arc::new(app);
    let listener = TcpListener::bind(addr).await?;
    loop {
        let (stream, _) = listener.accept().await?;
        let app = app.clone();
        tokio::spawn(async move {
            let io = TokioIo::new(stream);
            let svc = service_fn(move |req| serve_one(app.clone(), req));
            let _ = hyper::server::conn::http1::Builder::new().serve_connection(io, svc).await;
        });
    }
}
