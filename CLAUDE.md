# mfastapi 開発メモ
- 正本の設計は `DESIGN.md`。性能の主張は実測のみ(Milkhaの倍率は推定値)。
- 新規の自前APIはREST全廃方針(Connect/gRPC)に従う。FastAPI互換の入口は互換目的のみ。
- 次の一手: (1) Rust製ASGIサーバー/IR→OpenAPI全生成、(2) Mojo拡張(`PythonModuleBuilder`)の最小例、(3) スキーマ本体の比較、(4) Flareの版・ライセンス確認。

- 2026-11-14: path_matchesはStarlette互換(差分ファジング不一致0)。性能の結論はREADME参照。次の一手: 一括照合(route_first_match)をPythonModuleBuilder拡張で提供(固定費141ns)、Mojo版の最適化、`collect_ir`のルート表からpack_templatesを自動生成してStarletteのRouterへ差し込む。
- 2026-11-14: 拡張版RouteTable実装(先頭ヒット1.9倍〜外れ36倍)。次の一手: path_params(パラメータ値)の取り出し、先頭リテラルでの木(trie)化でN=200以上をさらに高速化、collect_irからStarlette Routerへ差し込み。
- 2026-11-14: RouteTable.match(path_params)実装済み(Starlette比1.1〜2.1倍、不一致0)。trieは見送り(理由はREADME)。次の一手: collect_irのルート表からRouteTableを作りStarletteのRouter照合へ差し込む(スコープ更新・405/redirect_slashesの扱い)。
