//! FastAPIM HTTP server layer (Rust). Routing uses the Starlette-compatible route table from `fastapim-core`; validation errors are
//! FastAPI/Pydantic-identical 422 responses; `/openapi.json` (OpenAPI 3.1) and `/docs` are served. Handlers are plain Rust closures
//! (stage C) or call into embedded Python (stage B, feature `python`). Only GET is implemented (others -> 405).
use fastapim_core::matcher::Table;
use fastapim_core::{parse_int, query_last};
use serde_json::{json, Map, Value};
use std::collections::HashMap;

#[cfg(feature = "python")]
pub mod pybridge;
pub mod server;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Int,
    Str,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Loc {
    Path,
    Query,
}

pub struct Param {
    pub name: &'static str,
    pub loc: Loc,
    pub kind: Kind,
    pub required: bool,
    pub default_int: i64,
}

impl Param {
    pub fn path(name: &'static str, kind: Kind) -> Param {
        Param { name, loc: Loc::Path, kind, required: true, default_int: 0 }
    }
    pub fn query(name: &'static str, kind: Kind) -> Param {
        Param { name, loc: Loc::Query, kind, required: true, default_int: 0 }
    }
    pub fn default_int(mut self, v: i64) -> Param {
        self.required = false;
        self.default_int = v;
        self
    }
}

pub enum Val {
    Int(i64),
    Str(String),
}

#[derive(Default)]
pub struct Args(HashMap<&'static str, Val>);

impl Args {
    pub fn int(&self, name: &str) -> i64 {
        match self.0.get(name) {
            Some(Val::Int(v)) => *v,
            _ => 0,
        }
    }
    pub fn str(&self, name: &str) -> &str {
        match self.0.get(name) {
            Some(Val::Str(s)) => s,
            _ => "",
        }
    }
}

pub struct Resp {
    pub status: u16,
    pub ctype: &'static str,
    pub body: String,
}

impl Resp {
    pub fn json(status: u16, body: String) -> Resp {
        Resp { status, ctype: "application/json", body }
    }
    pub fn detail(status: u16, msg: &str) -> Resp {
        Resp::json(status, json!({ "detail": msg }).to_string())
    }
}

pub type Handler = Box<dyn Fn(&Args) -> Resp + Send + Sync>;

pub struct Route {
    pub path: &'static str, // FastAPI style, e.g. "/fib/{n}"
    pub name: &'static str,
    pub params: Vec<Param>,
    pub returns: Kind,
    pub handler: Handler,
}

pub struct App {
    routes: Vec<Route>,
    table: Table,
}

fn hexval(c: u8) -> Option<u8> {
    (c as char).to_digit(16).map(|d| d as u8)
}

/// Percent-decode a URL path like Starlette (`unquote`: bytes -> UTF-8 with replacement; `+` stays `+`).
fn unquote(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let (Some(h), Some(l)) = (hexval(b[i + 1]), hexval(b[i + 2])) {
                out.push(h * 16 + l);
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn title(name: &str) -> String {
    let mut out = String::new();
    let mut up = true;
    for c in name.chars() {
        if c == '_' {
            out.push(' ');
            up = true;
        } else if up {
            out.extend(c.to_uppercase());
            up = false;
        } else {
            out.push(c);
        }
    }
    out
}

fn op_id(name: &str, path: &str) -> String {
    let mut s: String = name.chars().chain(path.chars()).map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect();
    s.push_str("_get");
    s
}

impl App {
    pub fn new(routes: Vec<Route>) -> Result<App, String> {
        let mut table = Table::new();
        for r in &routes {
            table.add(r.path.as_bytes()).map_err(|c| format!("bad route {}: {}", r.path, c))?;
        }
        Ok(App { routes, table })
    }

    pub fn openapi(&self) -> String {
        let mut paths = Map::new();
        for r in &self.routes {
            let params: Vec<Value> = r
                .params
                .iter()
                .map(|p| {
                    let mut schema = Map::new();
                    schema.insert("type".into(), json!(if p.kind == Kind::Int { "integer" } else { "string" }));
                    if !p.required && p.kind == Kind::Int {
                        schema.insert("default".into(), json!(p.default_int));
                    }
                    schema.insert("title".into(), json!(title(p.name)));
                    json!({"name": p.name, "in": if p.loc == Loc::Path { "path" } else { "query" }, "required": p.required, "schema": schema})
                })
                .collect();
            let mut op = Map::new();
            op.insert("summary".into(), json!(title(r.name)));
            op.insert("operationId".into(), json!(op_id(r.name, r.path)));
            if !params.is_empty() {
                op.insert("parameters".into(), json!(params));
            }
            let mut responses = Map::new();
            responses.insert(
                "200".into(),
                json!({"description": "Successful Response", "content": {"application/json": {"schema": {
                    "type": if r.returns == Kind::Int { "integer" } else { "string" }, "title": format!("Response {}", title(r.name))}}}}),
            );
            if !r.params.is_empty() {
                responses.insert(
                    "422".into(),
                    json!({"description": "Validation Error", "content": {"application/json": {"schema": {"$ref": "#/components/schemas/HTTPValidationError"}}}}),
                );
            }
            op.insert("responses".into(), Value::Object(responses));
            paths.insert(r.path.to_string(), json!({ "get": op }));
        }
        json!({
            "openapi": "3.1.0",
            "info": {"title": "FastAPI", "version": "0.1.0"},
            "paths": paths,
            "components": {"schemas": {
                "HTTPValidationError": {"properties": {"detail": {"items": {"$ref": "#/components/schemas/ValidationError"}, "type": "array", "title": "Detail"}}, "type": "object", "title": "HTTPValidationError"},
                "ValidationError": {"properties": {"loc": {"items": {"anyOf": [{"type": "string"}, {"type": "integer"}]}, "type": "array", "title": "Location"},
                    "msg": {"type": "string", "title": "Message"}, "type": {"type": "string", "title": "Error Type"}, "input": {"title": "Input"}, "ctx": {"type": "object", "title": "Context"}},
                    "type": "object", "required": ["loc", "msg", "type"], "title": "ValidationError"}
            }}
        })
        .to_string()
    }

    pub fn docs_html() -> String {
        concat!(
            "<!DOCTYPE html><html><head><link type=\"text/css\" rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css\">",
            "<title>FastAPI - Swagger UI</title></head><body><div id=\"swagger-ui\"></div>",
            "<script src=\"https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js\"></script>",
            "<script>const ui = SwaggerUIBundle({url: \"/openapi.json\", dom_id: \"#swagger-ui\", presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset], layout: \"BaseLayout\", deepLinking: true})</script></body></html>"
        )
        .to_string()
    }

    /// Handle one GET request (raw, still percent-encoded path and raw query string).
    pub fn handle(&self, raw_path: &str, query: &str) -> Resp {
        let path = unquote(raw_path);
        match path.as_str() {
            "/openapi.json" => return Resp::json(200, self.openapi()),
            "/docs" => return Resp { status: 200, ctype: "text/html; charset=utf-8", body: App::docs_html() },
            "/health" => return Resp::json(200, "{\"status\":\"ok\"}".into()),
            _ => {}
        }
        let idx = self.table.first_match_from(path.as_bytes(), 0);
        if idx < 0 {
            return Resp::detail(404, "Not Found");
        }
        let route = &self.routes[idx as usize];
        // path params: whole-segment {name} / {name:type}
        let mut pvals: HashMap<&str, &str> = HashMap::new();
        let tsegs: Vec<&str> = route.path.split('/').collect();
        let psegs: Vec<&str> = path.split('/').collect();
        if !route.path.contains(":path}") && tsegs.len() == psegs.len() {
            for (t, p) in tsegs.iter().zip(psegs.iter()) {
                if t.starts_with('{') && t.ends_with('}') {
                    let name = t[1..t.len() - 1].split(':').next().unwrap_or("");
                    pvals.insert(name, p);
                }
            }
        }
        let mut errors: Vec<Value> = Vec::new();
        let mut args = Args::default();
        let mut ordered: Vec<&Param> = route.params.iter().filter(|p| p.loc == Loc::Path).collect();
        ordered.extend(route.params.iter().filter(|p| p.loc == Loc::Query));
        for p in ordered {
            let loc = if p.loc == Loc::Path { "path" } else { "query" };
            let raw: Option<String> = match p.loc {
                Loc::Path => pvals.get(p.name).map(|s| s.to_string()),
                Loc::Query => query_last(query.as_bytes(), p.name.as_bytes()).map(|v| String::from_utf8_lossy(&v).into_owned()),
            };
            match raw {
                None if p.required => {
                    errors.push(json!({"type": "missing", "loc": [loc, p.name], "msg": "Field required", "input": Value::Null}));
                }
                None => {
                    args.0.insert(p.name, Val::Int(p.default_int));
                }
                Some(s) => match p.kind {
                    Kind::Str => {
                        args.0.insert(p.name, Val::Str(s));
                    }
                    Kind::Int => match parse_int(s.as_bytes()) {
                        Ok(v) => {
                            args.0.insert(p.name, Val::Int(v));
                        }
                        Err(_) => {
                            errors.push(json!({"type": "int_parsing", "loc": [loc, p.name],
                                "msg": "Input should be a valid integer, unable to parse string as an integer", "input": s}));
                        }
                    },
                },
            }
        }
        if !errors.is_empty() {
            return Resp::json(422, json!({ "detail": errors }).to_string());
        }
        (route.handler)(&args)
    }
}
