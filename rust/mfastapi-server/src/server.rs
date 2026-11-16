//! hyper/tokio HTTP/1.1 front end for `App`. Handlers run on the blocking pool so CPU-heavy handlers never stall the reactor.
use crate::{App, Resp};
use bytes::Bytes;
use http_body_util::{BodyExt, Full, Limited};
use hyper::{body::Incoming, service::service_fn, Method, Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use std::sync::Arc;
use tokio::net::TcpListener;

/// Request bodies above this size get 413.
const MAX_BODY: usize = 1024 * 1024;

fn to_response(r: Resp) -> Response<Full<Bytes>> {
    let mut b = Response::builder().status(StatusCode::from_u16(r.status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR)).header("content-type", r.ctype);
    if let Some(a) = &r.allow {
        b = b.header("allow", a.as_str());
    }
    b.body(Full::new(Bytes::from(r.body)))
        .unwrap_or_else(|_| Response::new(Full::new(Bytes::new())))
}

async fn serve_one(app: Arc<App>, req: Request<Incoming>) -> Result<Response<Full<Bytes>>, std::convert::Infallible> {
    let method = req.method().clone();
    let path = req.uri().path().to_string();
    let query = req.uri().query().unwrap_or("").to_string();
    let body = match Limited::new(req.into_body(), MAX_BODY).collect().await {
        Ok(c) => c.to_bytes(),
        Err(_) => return Ok(to_response(Resp::detail(413, "Request Entity Too Large"))),
    };
    let m = method.as_str().to_string();
    let r = tokio::task::spawn_blocking(move || app.handle(&m, &path, &query, &body))
        .await
        .unwrap_or_else(|_| Resp::detail(500, "Internal Server Error"));
    let mut resp = to_response(r);
    if method == Method::HEAD {
        *resp.body_mut() = Full::new(Bytes::new());
    }
    Ok(resp)
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
