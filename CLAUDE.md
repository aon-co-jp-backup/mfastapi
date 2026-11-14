# mfastapi 開発メモ
- 正本の設計は `DESIGN.md`。性能の主張は実測のみ(Milkhaの倍率は推定値)。
- 新規の自前APIはREST全廃方針(Connect/gRPC)に従う。FastAPI互換の入口は互換目的のみ。
- 次の一手: (1) Rust製ASGIサーバー/IR→OpenAPI全生成、(2) Mojo拡張(`PythonModuleBuilder`)の最小例、(3) スキーマ本体の比較、(4) Flareの版・ライセンス確認。
