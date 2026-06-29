# コントリビューションガイド

この文書は `CONTRIBUTING.md` の日本語要約です。内容に差異がある場合は
英語版を優先してください。

FlowBrigade は時間制御ユーティリティに焦点を当てた小さなライブラリです。
変更は、retry、backoff、rate limit、quota、fallback、circuit breaker、
bulkhead、timeout、observability などの責務に収まるようにしてください。

## 歓迎する貢献

- 足りないテストの追加
- edge case や異常系のテスト
- バグ修正と regression test
- README、docs、recipes の改善
- adapter package の互換性テスト

バグを見つけた場合、可能であれば修正と再発防止テストを同じ pull request
に含めてください。

## テスト方針

新しい挙動は TDD を推奨します。

1. 先に `tests/` に focused test を追加する
2. 期待した理由で失敗することを確認する
3. 最小限の明確な実装を入れる
4. `tests/all.nim` を実行する
5. 公開挙動が変わる場合は README や docs を更新する

時間依存のテストでは、実時間の sleep ではなく internal manual time source を
使ってください。

## 実行コマンド

```sh
nim r --nimcache:/tmp/flowbrigade-nimcache -p:src tests/all.nim
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim test
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim snippets
```

## 範囲外

- public `Clock` API
- timezone / calendar math / date formatting
- HTTP framework 固有 middleware
- rate limiting と無関係な generic cache/storage abstraction

難しい箇所を避けず、必要な場合はテストを厚めに追加してください。
