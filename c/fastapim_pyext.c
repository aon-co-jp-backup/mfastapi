/* fastapim_cext: C版コンパイル済みルート表(fastapim_cabi.c)をCPython拡張として公開する。
 * Mojoが動かないOS(Windows等)でも、ctypesより呼び出し費用を大きく減らせる(Python 3専用)。
 * RouteTable(list_of_str): size(), first_match(path), first_match_from(path, start)
 * 戻り値: 番号 / -1=なし。バックトラック上限は RuntimeError、未知の型名・重複等は ValueError。 */
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include "fastapim_cabi.c"

typedef struct { PyObject_HEAD void *tbl; int32_t n; } RT;

static int rt_init(RT *self, PyObject *args, PyObject *kw) {
    PyObject *lst, *seq;
    Py_ssize_t i, n;
    (void)kw;
    if (!PyArg_ParseTuple(args, "O", &lst)) return -1;
    seq = PySequence_Fast(lst, "RouteTable expects a list of str");
    if (!seq) return -1;
    if (self->tbl) { fastapim_table_free(self->tbl); self->tbl = NULL; }
    self->tbl = fastapim_table_new();
    if (!self->tbl) { Py_DECREF(seq); PyErr_NoMemory(); return -1; }
    n = PySequence_Fast_GET_SIZE(seq);
    for (i = 0; i < n; i++) {
        Py_ssize_t len;
        const char *s = PyUnicode_AsUTF8AndSize(PySequence_Fast_GET_ITEM(seq, i), &len);
        int32_t r;
        if (!s) { Py_DECREF(seq); return -1; }
        r = fastapim_table_add(self->tbl, (const uint8_t *)s, (int64_t)len);
        if (r != 0) {
            Py_DECREF(seq);
            PyErr_Format(PyExc_ValueError, "template %zd rejected (code %d)", i, (int)r);
            return -1;
        }
    }
    Py_DECREF(seq);
    self->n = (int32_t)n;
    return 0;
}

static void rt_dealloc(RT *self) {
    if (self->tbl) fastapim_table_free(self->tbl);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

static PyObject *rt_find(RT *self, PyObject *args) {
    PyObject *path;
    int start = 0;
    Py_ssize_t len;
    const char *s;
    int32_t r;
    if (!PyArg_ParseTuple(args, "U|i", &path, &start)) return NULL;
    s = PyUnicode_AsUTF8AndSize(path, &len);
    if (!s) return NULL;
    r = fastapim_table_first_match_from(self->tbl, (const uint8_t *)s, (int64_t)len, start);
    if (r == -3) { PyErr_SetString(PyExc_RuntimeError, "path matching gave up (backtracking budget)"); return NULL; }
    return PyLong_FromLong((long)r);
}

static PyObject *rt_size(RT *self, PyObject *noargs) { (void)noargs; return PyLong_FromLong((long)self->n); }

static PyMethodDef rt_methods[] = {
    {"first_match", (PyCFunction)rt_find, METH_VARARGS, "first_match(path) -> index or -1"},
    {"first_match_from", (PyCFunction)rt_find, METH_VARARGS, "first_match_from(path, start) -> index or -1"},
    {"size", (PyCFunction)rt_size, METH_NOARGS, "number of templates"},
    {NULL, NULL, 0, NULL}
};

static PyTypeObject RT_Type = {
    PyVarObject_HEAD_INIT(NULL, 0)
    "fastapim_cext.RouteTable",    /* tp_name */
    sizeof(RT),                    /* tp_basicsize */
};

static struct PyModuleDef moddef = {PyModuleDef_HEAD_INIT, "fastapim_cext", NULL, -1, NULL};

PyMODINIT_FUNC PyInit_fastapim_cext(void) {
    PyObject *m;
    RT_Type.tp_dealloc = (destructor)rt_dealloc;
    RT_Type.tp_flags = Py_TPFLAGS_DEFAULT;
    RT_Type.tp_methods = rt_methods;
    RT_Type.tp_init = (initproc)rt_init;
    RT_Type.tp_new = PyType_GenericNew;
    if (PyType_Ready(&RT_Type) < 0) return NULL;
    m = PyModule_Create(&moddef);
    if (!m) return NULL;
    Py_INCREF(&RT_Type);
    if (PyModule_AddObject(m, "RouteTable", (PyObject *)&RT_Type) < 0) { Py_DECREF(&RT_Type); Py_DECREF(m); return NULL; }
    return m;
}
