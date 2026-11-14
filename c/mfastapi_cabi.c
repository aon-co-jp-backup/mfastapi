/* mfastapi C ABI portable reference implementation (C99).
 * Same functions and behavior as mojo/mfastapi_cabi.mojo. For OSes where Mojo does not run (native Windows, Android, iOS, BSD).
 * Depends on the C standard library only.
 *
 * mfastapi_path_matches follows Starlette's compile_path()/re.match semantics:
 *   {name} {name:str} -> [^/]+     {name:path} -> .*     {name:int} -> [0-9]+
 *   {name:float} -> [0-9]+(\.[0-9]+)?      {name:uuid} -> 8-4-4-4-12 hex with optional '-'
 *   a '{' that is not a valid {name[:type]} is a literal; params may sit inside a segment; backtracking like `re`.
 *   '$' also accepts one trailing '\n' (Python re behavior).
 * Return: 1 match, 0 no match, -1 unknown convertor type (Starlette asserts), -2 gave up (backtracking budget). */
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define MFASTAPI_EXPORT __declspec(dllexport)
#else
#define MFASTAPI_EXPORT __attribute__((visibility("default")))
#endif

MFASTAPI_EXPORT int32_t mfastapi_abi_version(void) { return 1; }

MFASTAPI_EXPORT int64_t mfastapi_add(int64_t a, int64_t b) { return (int64_t)((uint64_t)a + (uint64_t)b); }

enum { K_STR, K_PATH, K_INT, K_FLOAT, K_UUID };
#define BUDGET 200000

typedef struct {
    const uint8_t *t; int64_t tl;
    const uint8_t *p; int64_t pl;
    int64_t steps;
} ctx;

static int is_alpha_(uint8_t c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }
static int is_alnum_(uint8_t c) { return is_alpha_(c) || (c >= '0' && c <= '9'); }
static int is_digit_(uint8_t c) { return c >= '0' && c <= '9'; }
static int is_hex_(uint8_t c) { return is_digit_(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }

/* t[i] が '{' のとき、{name} / {name:type} として有効なら終端(次の位置)と種別を返す。0=リテラル, 1=有効, -1=型名が不明 */
static int parse_param(const ctx *c, int64_t i, int64_t *next, int *kind) {
    int64_t j = i + 1;
    if (j >= c->tl || !is_alpha_(c->t[j])) return 0;
    while (j < c->tl && is_alnum_(c->t[j])) j++;
    *kind = K_STR;
    if (j < c->tl && c->t[j] == ':') {
        int64_t s = j + 1, e = s;
        if (e >= c->tl || !is_alpha_(c->t[e])) return 0;
        while (e < c->tl && is_alnum_(c->t[e])) e++;
        if (e >= c->tl || c->t[e] != '}') return 0;
        int64_t n = e - s; const uint8_t *q = c->t + s;
        if (n == 3 && q[0] == 's' && q[1] == 't' && q[2] == 'r') *kind = K_STR;
        else if (n == 4 && q[0] == 'p' && q[1] == 'a' && q[2] == 't' && q[3] == 'h') *kind = K_PATH;
        else if (n == 3 && q[0] == 'i' && q[1] == 'n' && q[2] == 't') *kind = K_INT;
        else if (n == 5 && q[0] == 'f' && q[1] == 'l' && q[2] == 'o' && q[3] == 'a' && q[4] == 't') *kind = K_FLOAT;
        else if (n == 4 && q[0] == 'u' && q[1] == 'u' && q[2] == 'i' && q[3] == 'd') *kind = K_UUID;
        else return -1;
        *next = e + 1;
        return 1;
    }
    if (j >= c->tl || c->t[j] != '}') return 0;
    *next = j + 1;
    return 1;
}

static int match_from(ctx *c, int64_t ti, int64_t pi);

static int try_ends(ctx *c, int64_t ti, int64_t from, int64_t hi, int64_t lo) {
    /* 長い方から短い方へ(正規表現の貪欲+バックトラックと同じ順) */
    for (int64_t e = hi; e >= lo; e--) {
        /* UTF-8の文字の途中では区切らない(Pythonの`re`はコードポイント単位) */
        if (e < c->pl && (c->p[e] & 0xC0) == 0x80) continue;
        if (++c->steps > BUDGET) return -2;
        int r = match_from(c, ti, e);
        if (r != 0) return r;
    }
    (void)from;
    return 0;
}

static int match_from(ctx *c, int64_t ti, int64_t pi) {
    while (ti < c->tl) {
        uint8_t ch = c->t[ti];
        if (ch == '{') {
            int64_t nx = 0; int kind = 0;
            int pr = parse_param(c, ti, &nx, &kind);
            if (pr < 0) return -1;
            if (pr > 0) {
                int64_t e;
                switch (kind) {
                case K_STR:
                    for (e = pi; e < c->pl && c->p[e] != '/'; e++) {}
                    return e > pi ? try_ends(c, nx, pi, e, pi + 1) : 0;
                case K_PATH:
                    for (e = pi; e < c->pl && c->p[e] != '\n'; e++) {}
                    return try_ends(c, nx, pi, e, pi);
                case K_INT:
                    for (e = pi; e < c->pl && is_digit_(c->p[e]); e++) {}
                    return e > pi ? try_ends(c, nx, pi, e, pi + 1) : 0;
                case K_FLOAT: {
                    int64_t d1;
                    for (d1 = pi; d1 < c->pl && is_digit_(c->p[d1]); d1++) {}
                    if (d1 == pi) return 0;
                    if (d1 + 1 < c->pl && c->p[d1] == '.' && is_digit_(c->p[d1 + 1])) {
                        int64_t d2 = d1 + 1;
                        while (d2 < c->pl && is_digit_(c->p[d2])) d2++;
                        int r = try_ends(c, nx, pi, d2, d1 + 2);
                        if (r != 0) return r;
                    }
                    return try_ends(c, nx, pi, d1, pi + 1);
                }
                default: { /* K_UUID: 8-4-4-4-12、'-'は省略可 */
                    static const int g[5] = {8, 4, 4, 4, 12};
                    int64_t q = pi;
                    for (int k = 0; k < 5; k++) {
                        if (k > 0 && q < c->pl && c->p[q] == '-') q++;
                        for (int n = 0; n < g[k]; n++, q++)
                            if (q >= c->pl || !is_hex_(c->p[q])) return 0;
                    }
                    pi = q; ti = nx; continue;
                }
                }
            }
        }
        if (pi >= c->pl || c->p[pi] != ch) return 0;
        ti++; pi++;
    }
    /* '$' : 末尾、または末尾の改行1つ手前 */
    return (pi == c->pl || (pi == c->pl - 1 && c->p[pi] == '\n')) ? 1 : 0;
}

MFASTAPI_EXPORT int32_t mfastapi_path_matches(const uint8_t *tpl, int64_t tpl_len, const uint8_t *path, int64_t path_len) {
    ctx c;
    if (tpl_len < 0 || path_len < 0) return 0;
    c.t = tpl; c.tl = tpl_len; c.p = path; c.pl = path_len; c.steps = 0;
    return (int32_t)match_from(&c, 0, 0);
}

/* ルート表をまとめて照合する: tpls は '\n' 区切りのテンプレート列。最初に一致した行番号(0始まり)を返す。
 * -1=一致なし, -2=不正な型名を含むテンプレートがあった, -3=バックトラック上限で断念。 */
MFASTAPI_EXPORT int32_t mfastapi_route_first_match(const uint8_t *tpls, int64_t tpls_len, const uint8_t *path, int64_t path_len) {
    int64_t start = 0;
    int32_t idx = 0;
    if (tpls_len < 0 || path_len < 0) return -1;
    for (int64_t i = 0; i <= tpls_len; i++) {
        if (i == tpls_len || tpls[i] == '\n') {
            ctx c;
            c.t = tpls + start; c.tl = i - start; c.p = path; c.pl = path_len; c.steps = 0;
            int r = match_from(&c, 0, 0);
            if (r == 1) return idx;
            if (r == -1) return -2;
            if (r == -2) return -3;
            idx++;
            start = i + 1;
        }
    }
    return -1;
}
