//! Stage B bridge: call user handlers written in Python (embedded interpreter; every call takes the GIL properly).
use crate::Resp;
use pyo3::prelude::*;

pub fn add_path(dir: &str) {
    Python::attach(|py| {
        if let Ok(sys) = PyModule::import(py, "sys") {
            if let Ok(path) = sys.getattr("path") {
                let _ = path.call_method1("insert", (0, dir));
            }
        }
    });
}

/// Call `pyhandlers.<func>(arg)` (str -> str, the returned string is the JSON body).
pub fn call(func: &str, arg: &str) -> Resp {
    let r: PyResult<String> = Python::attach(|py| {
        let m = PyModule::import(py, "pyhandlers")?;
        m.getattr(func)?.call1((arg,))?.extract::<String>()
    });
    match r {
        Ok(body) => Resp::json(200, body),
        Err(e) => Resp::detail(500, &format!("python handler error: {e}")),
    }
}
