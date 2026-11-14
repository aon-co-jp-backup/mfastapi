//! Python extension `fastapim_rust`: the Rust core with no ctypes overhead. API-compatible with fastapim_cext.RouteTable.
use fastapim_core::matcher::Table;
use fastapim_core::{parse_int as core_parse_int, query_last as core_query_last, IntError};
use pyo3::exceptions::{PyOverflowError, PyRuntimeError, PyValueError};
use pyo3::prelude::*;

#[pyclass(frozen, name = "RouteTable")]
struct RouteTable {
    t: Table,
}

#[pymethods]
impl RouteTable {
    #[new]
    fn new(templates: Vec<String>) -> PyResult<Self> {
        let mut t = Table::new();
        for s in &templates {
            t.add(s.as_bytes()).map_err(|c| PyValueError::new_err(format!("template rejected (code {c}): {s:?}")))?;
        }
        Ok(RouteTable { t })
    }

    fn size(&self) -> usize {
        self.t.len()
    }

    #[pyo3(signature = (path, start = 0))]
    fn first_match_from(&self, path: &str, start: i32) -> PyResult<i32> {
        match self.t.first_match_from(path.as_bytes(), start) {
            -3 => Err(PyRuntimeError::new_err("path matching gave up (backtracking budget)")),
            r => Ok(r),
        }
    }

    fn first_match(&self, path: &str) -> PyResult<i32> {
        self.first_match_from(path, 0)
    }
}

/// Pydantic-lax int from str: int, or None when Pydantic would reject it. OverflowError beyond int64, ValueError when too long.
#[pyfunction]
fn parse_int(s: &str) -> PyResult<Option<i64>> {
    match core_parse_int(s.as_bytes()) {
        Ok(v) => Ok(Some(v)),
        Err(IntError::Invalid) => Ok(None),
        Err(IntError::OutOfRange) => Err(PyOverflowError::new_err("integer out of int64 range")),
        Err(IntError::TooLong) => Err(PyValueError::new_err("input too long")),
    }
}

/// Last decoded value of `name` in a raw query string, or None.
#[pyfunction]
fn query_last(query: &str, name: &str) -> Option<String> {
    core_query_last(query.as_bytes(), name.as_bytes()).map(|v| String::from_utf8_lossy(&v).into_owned())
}

#[pymodule]
fn fastapim_rust(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_class::<RouteTable>()?;
    m.add_function(wrap_pyfunction!(parse_int, m)?)?;
    m.add_function(wrap_pyfunction!(query_last, m)?)?;
    Ok(())
}
