/* mfastapi C ABI portable reference implementation (C99).
 * Same functions and behavior as mojo/mfastapi_cabi.mojo. For OSes where Mojo does not run (native Windows, Android, iOS, BSD).
 * Depends on the C standard library only. */
#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define MFASTAPI_EXPORT __declspec(dllexport)
#else
#define MFASTAPI_EXPORT __attribute__((visibility("default")))
#endif

MFASTAPI_EXPORT int32_t mfastapi_abi_version(void) { return 1; }

MFASTAPI_EXPORT int64_t mfastapi_add(int64_t a, int64_t b) { return (int64_t)((uint64_t)a + (uint64_t)b); }

MFASTAPI_EXPORT int32_t mfastapi_path_matches(const uint8_t *tpl, int64_t tpl_len, const uint8_t *path, int64_t path_len) {
    int64_t i = 0, j = 0;
    if (tpl_len < 0 || path_len < 0) return 0;
    for (;;) {
        int64_t ie = i, je = j;
        while (ie < tpl_len && tpl[ie] != '/') ie++;
        while (je < path_len && path[je] != '/') je++;
        int is_param = (ie - i >= 2) && tpl[i] == '{' && tpl[ie - 1] == '}';
        if (is_param) {
            if (je == j) return 0;
        } else {
            if (ie - i != je - j) return 0;
            for (int64_t k = 0; k < ie - i; k++)
                if (tpl[i + k] != path[j + k]) return 0;
        }
        int t_end = ie >= tpl_len, p_end = je >= path_len;
        if (t_end || p_end) return (t_end && p_end) ? 1 : 0;
        i = ie + 1;
        j = je + 1;
    }
}
