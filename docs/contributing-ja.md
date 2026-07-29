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

## ブランチとリリース

`devel` を統合ブランチ、`main` をリリースブランチとして運用します。

- feature、fix、docs などの作業ブランチは、最新の `devel` から作成する
- すべての pull request のマージ先は `devel` とする
- 最新の push 後に必要な review が通過し、review thread をすべて解決してから
  `devel` にマージする。CI はすべての pull request で実行するが、Ruleset の
  マージ必須条件にはしない
- 変更がある程度たまったら、`devel` から `main` への release pull request を作成する
- release pull request のマージ後、`main` のマージコミットに annotated tag を作成してリリースする

リリース時は CHANGELOG とバージョン情報を更新したうえで、次のようにタグを作成します。

```sh
git switch main
git pull --ff-only origin main
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

`main` と `devel` は Ruleset で保護します。削除と force push を禁止し、最新 push 後の
1 件の承認、review thread の全解決を必須にします。merge、squash、rebase の各方式を
利用できます。新しい pull request のデフォルトのマージ先は `devel` に設定してください。

## 範囲外

- public `Clock` API
- timezone / calendar math / date formatting
- HTTP framework 固有 middleware
- rate limiting と無関係な generic cache/storage abstraction

難しい箇所を避けず、必要な場合はテストを厚めに追加してください。
