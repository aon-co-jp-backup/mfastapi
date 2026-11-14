# -*- coding: utf-8 -*-
"""path_matches を Starlette の compile_path と突き合わせる差分ファザー(Python 3専用)。
使い方: FASTAPIM_LIB=<lib> python bench/diff_starlette.py [件数]"""
import os, random, sys, collections
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "python", "fastapim"))
import native
from starlette.routing import compile_path

N = int(sys.argv[1]) if len(sys.argv) > 1 else 100000
rng = random.Random(333)

def gen_template():
    parts = []
    for _ in range(rng.randint(0, 4)):
        seg = ""
        for _ in range(rng.randint(1, 3)):
            r = rng.random()
            if r < 0.45: seg += rng.choice(["a", "b", "ab", "items", "v1", "-", "."])
            elif r < 0.75: seg += "{%s}" % rng.choice(["x", "y", "id", "x:int", "y:str", "n:float", "p:path", "u:uuid"])
            elif r < 0.85: seg += rng.choice(["{}", "{1x}", "{x y}", "{", "}"])  # 不正な波括弧
            else: seg += rng.choice(["é", "あ"])
        parts.append(seg)
    t = "/" + "/".join(parts)
    if rng.random() < 0.15: t += "/"
    return t

SAMPLES = ["a", "b", "ab", "items", "v1", "42", "0", "3.14", "x", "-", ".", "é", "あ",
           "123e4567-e89b-12d3-a456-426614174000", "123e4567e89b12d3a456426614174000", "", "1.", ".5", "٣"]

def gen_path(tpl):
    r = rng.random()
    if r < 0.5:  # テンプレートから一致しそうな物を作る
        out = ""
        i = 0
        import re
        for m in re.finditer(r"\{([a-zA-Z_][a-zA-Z0-9_]*)(:[a-zA-Z_][a-zA-Z0-9_]*)?\}", tpl):
            out += tpl[i:m.start()]
            kind = (m.group(2) or ":str")[1:]
            out += {"int": rng.choice(["42", "0", "x"]), "float": rng.choice(["3.14", "7", "1."]),
                    "uuid": rng.choice(SAMPLES[-6:-4]), "path": rng.choice(["a/b", "a", "", "a/b/c"])}.get(kind, rng.choice(["v", "42", "a-b", ""]))
            i = m.end()
        return out + tpl[i:]
    return "/" + "/".join(rng.choice(SAMPLES) for _ in range(rng.randint(0, 4)))

def starlette_match(tpl, path):
    rx, _, _ = compile_path(tpl)
    return rx.match(path) is not None

cats = collections.Counter(); examples = {}
errors = 0
for _ in range(N):
    tpl, path = gen_template(), gen_path(gen_template()) if False else None
    path = gen_path(tpl)
    try:
        want = starlette_match(tpl, path)
    except (AssertionError, ValueError):
        cats["starlette-rejects-template"] += 1; continue
    got = native.path_matches(tpl, path)
    if got != want:
        import re
        has = lambda p: re.search(p, tpl) is not None
        if has(r":(int|float|uuid|path)\}"): k = "typed-converter"
        elif has(r"\{[a-zA-Z_]\w*\}[^/]") or has(r"[^/]\{[a-zA-Z_]\w*\}"): k = "param-inside-segment"
        elif has(r"\{\}|\{1x\}|\{x y\}|\{(?![a-zA-Z_])|\}"): k = "invalid-braces"
        else: k = "other"
        cats[k] += 1; examples.setdefault(k, (tpl, path, want, got))
    else:
        cats["agree"] += 1
total = sum(v for k, v in cats.items() if k != "starlette-rejects-template")
print("cases=%d compared=%d" % (N, total))
for k, v in cats.most_common(): print("  %-28s %d" % (k, v))
for k, e in examples.items(): print("  e.g.[%s] tpl=%s path=%s starlette=%s fastapim=%s" % ((k,) + tuple(ascii(x) if isinstance(x,str) else x for x in e)))
