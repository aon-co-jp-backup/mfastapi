# -*- coding: utf-8 -*-
"""依存なしのスモークテスト(iOS/Androidなど、fastapiが入らない環境で mfastapi_cext を確認する)。"""
import mfastapi_cext as c

t = c.RouteTable(["/a/{x}", "/items/{id:int}", "/files/{p:path}", "/u/{u:uuid}", "/m/{f:float}", "/あ/{n}"])
assert t.size() == 6
cases = [("/a/1", 0), ("/items/42", 1), ("/items/x", -1), ("/files/a/b", 2), ("/files/", 2),
         ("/u/123e4567-e89b-12d3-a456-426614174000", 3), ("/m/3.14", 4), ("/m/3", 4), ("/m/x", -1),
         ("/あ/い", 5), ("/nope", -1), ("/a/", -1)]
for path, want in cases:
    got = t.first_match(path)
    assert got == want, (path, want, got)
assert t.first_match_from("/a/1", 1) == -1
try:
    c.RouteTable(["/x/{a:bogus}"])
    raise SystemExit("unknown convertor was accepted")
except ValueError:
    pass
print("mfastapi_cext smoke OK")
