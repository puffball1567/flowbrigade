# flowbrigade design notes

## Project direction

`flowbrigade` is a small Nim library for time-based control utilities.

It is not a Carbon-like date/time convenience library. Carbon-style features
should be built as a separate package.

## Japanese summary

`flowbrigade` は Nim 向けの時間制御ユーティリティです。

期間文字列の解析、失敗後の再試行、待ち時間ルール、実行回数の制限など、
時間に関わる制御処理を小さな部品として提供します。

Web 専用ではありません。API client、CLI、worker、batch job、Web service
などで使える汎用ライブラリとして設計します。

## In scope

- duration parsing and formatting
- backoff schedules
- retry helpers
- fallback helpers
- rate limiting
- usage budgets and quotas
- practical policy bundles
- policy validation reports
- opt-in control diagnostics
- observability export helpers
- keyed in-memory limiters
- throttle and debounce
- circuit breaker
- timeout tracking
- in-process bulkheads, including per-key bulkheads
- internal time source for deterministic tests

## Out of scope

- public `Clock` API
- `now`, `today`, `tomorrow`
- timezone handling
- calendar math
- date formatting
- relative time display such as "3 minutes ago"
- localization
- cron scheduling
- HTTP-framework-specific middleware
- Redis, Memcached, or database-backed storage in core

## Relationship to Carbon-style libraries

Carbon-style libraries mainly answer questions like:

- What time is it now?
- What is tomorrow?
- How do I format this date?
- How do I calculate calendar dates?
- How do I display relative time for humans?

`flowbrigade` answers different questions:

- How long should this operation wait?
- How do I parse `30s` from config?
- How should retries be spaced after failures?
- Which secondary provider may be tried after a primary failure?
- How many times may this action run per interval?
- How much of this tenant or API key's period budget remains?
- Which standard control pattern should I start from?
- Are the recent control signals telling me to inspect or tune something?
- How do I hand control events to my logging or metrics stack?
- How do I test time-dependent control logic without waiting in real time?

Because these are different domains, Carbon-style helpers should not be mixed
into this package.

## Feature explanations in Japanese

### Duration parsing / formatting

日本語では「期間文字列の解析・整形」です。

人間が書きやすい短い時間表記を Nim の `Duration` に変換したり、
`Duration` を短い文字列に戻したりします。

Examples:

- `"250ms"` means 250 milliseconds
- `"2s"` means 2 seconds
- `"1h30m"` means 1 hour and 30 minutes
- `"2d4h"` means 2 days and 4 hours

Use cases:

- config values such as `timeout = "30s"`
- CLI arguments such as `--interval 5m`
- retry and rate limit settings

### Backoff

日本語では「失敗後の待ち時間ルール」です。

`back off` は「一歩引く」「間隔を空ける」という意味です。
ライブラリの文脈では、処理が失敗したときにすぐ何度も再試行せず、
少し待ってから再試行するための待ち時間の決め方を指します。

Kinds:

- fixed backoff: 毎回同じ時間だけ待つ
- linear backoff: 失敗するたびに一定量ずつ長く待つ
- exponential backoff: 失敗するたびに倍々で長く待つ
- jitter: 待ち時間にランダムな揺らぎを入れる

`jitter` は、多数の client や worker が同時に失敗し、同時に再試行して
また同時に負荷をかける状況を避けるために使います。

### Retry

日本語では「再試行」です。

失敗する可能性のある処理を、決められた回数まで繰り返す機能です。
`backoff` は「各失敗後にどれだけ待つか」、`retry` は「実際に処理を
何回試すか」です。

Use cases:

- temporary network errors
- temporary database connection failures
- temporary file lock conflicts
- worker job retries

Retrying is not always safe. Users must decide whether the operation is safe to
run more than once, especially for side-effecting operations such as payments or
email delivery.

### Fallback

日本語では「代替経路への切り替え」です。

primary provider が失敗したときに、secondary provider、cache、degraded
implementation などを順番に試します。retry が「同じ処理をもう一度試す」
機能だとすると、fallback は「別の経路を試す」機能です。

Fallback is only appropriate when the secondary result is semantically
acceptable. It should not be used to duplicate unsafe side effects such as
payments or irreversible writes.

`tryInOrder` and `tryInOrderAsync` return metadata about the provider that
succeeded, failed providers, attempts, and the last error. A provider may also
be guarded by a `CircuitBreaker`; open circuits are skipped before the provider
call runs.

### Rate limiting

日本語では「実行回数の制限」または「流量制限」です。

一定時間に実行できる回数を制限する機能です。

Examples:

- allow up to 10 actions per second
- allow up to 100 actions per minute
- allow up to 1000 actions per user per hour

Kinds:

- token bucket: 一定速度で token が補充され、処理するたびに token を消費する
- GCRA: 理論上の次回到着時刻を管理し、高スループットの流量を滑らかにする
- fixed window: 固定された時間枠ごとに回数を数える
- sliding window: 直前の時間枠も重み付けして、窓の切り替わりで急に流量が増えるのを抑える
- keyed limiter: user id, API token, job name などの key ごとに制限する
- compound limiter: 複数の制限をまとめ、全部通る場合だけ許可する
- stored fixed window: Redis などの外部 storage に状態を置ける固定窓 limiter

`token bucket` is useful when short bursts should be allowed.
`GCRA` is useful when high-throughput request flow should be smoothed with
compact state.
`fixed window` is simple and easy to understand.
`sliding window` is useful when boundary spikes should be smoothed.

All rate limiters expose:

- `allow`: returns only `bool` and consumes capacity when allowed
- `consume`: consumes capacity when allowed and returns `RateLimitResult`
- `inspect`: returns `RateLimitResult` without consuming capacity

`RateLimitResult` includes whether the action is allowed, the configured limit,
remaining capacity, retry delay, and reset delay.

HTTP-facing callers can derive `RateLimit-Limit`, `RateLimit-Remaining`,
`RateLimit-Reset`, and `Retry-After` headers from `RateLimitResult`. This keeps
framework integrations small and avoids tying the core package to one web stack.
Callers that should pause instead of failing immediately can use `wait` or
`waitAsync` with an application-provided sleep function.

Keys should be built through `rateLimitKey` or `opaqueRateLimitKey` when they are
derived from multiple parts or sensitive identifiers. `opaqueRateLimitKey` takes
a caller-provided fingerprint function so applications can choose their own
hashing or HMAC implementation.

Distributed storage is designed on top of this result API. Redis is the first
supported backend because it supports expiry and atomic updates well. Memcached
support is intentionally narrower because its atomic update model is different.

### Budget / quota

日本語では「利用量の予算」または「割当量」です。

rate limiting が「今この瞬間の流量を抑える」機能だとすると、budget は
「この期間にどれだけ使ったか」を追跡する機能です。

Examples:

- 1 tenant may use up to 100,000 units per month
- 1 API key may spend up to 10,000 tokens per day
- 1 worker class may run up to 500 expensive jobs per hour

`BudgetLedger` stores usage by key, resets it after the configured period, and
returns `BudgetResult` with `used`, `remaining`, `retryAfter`, and `resetAfter`.
It is useful when a caller needs fairness, cost control, or long-period quota
metadata rather than only short-term request smoothing.

### Policy builders

日本語では「実戦パターンの組み立て済み設定」です。

個別の limiter や retry を毎回手で組み合わせる代わりに、よくある制御
パターンを小さな束として作ります。

Examples:

- login protection: account/id 単位の試行回数を抑える
- API abuse protection: per-identity と global burst を組み合わせる
- third-party API client: rate limit、retry、circuit breaker をまとめる
- worker backpressure: throughput、retry、circuit breaker、bulkhead をまとめる
- multi-tenant quota: short burst と period budget を組み合わせる

Policy builders do not hide the underlying pieces. They return a `FlowPolicy`
with a `LimiterRegistry` and optional `BudgetConfig`, `RetryConfig`,
`CircuitBreakerConfig`, or bulkhead capacity so applications can adopt only the
parts they need.

Policy validation reports are non-throwing checks for startup, config loading,
and dry-run tooling. They verify that the primary limiter exists and that
required optional pieces such as quota, retry, circuit breaker, or bulkhead
configuration are present before the application starts serving work.

### Bulkhead

日本語では「同時実行の区画制限」です。

処理全体、または tenant / queue / job class などの key ごとに、同時に走れる
処理数を制限します。失敗した依存先や重いジョブが全体の worker を使い切る
ことを避けるための部品です。

FlowBrigade の bulkhead は単一プロセス内の permit counter です。キュー管理、
優先度 scheduling、分散 lock は持ちません。複数 thread で同じ instance を
共有する場合は、利用側で mutex などの同期を行います。

### Control diagnostics

日本語では「制御状態の診断」です。

FlowBrigade は retry 回数、rate limit、circuit breaker、bulkhead などを
勝手に変更しません。利用側が明示的に渡した `ControlSignal` を集計し、
`ControlReport` と `ControlHint` を返すだけです。

Examples:

- failure/timeout が多いので downstream を確認する
- failure が多いので retry 回数を減らすことを検討する
- rate-limit denial が多いので abuse や大きすぎる caller を確認する
- bulkhead full が多いので intake や concurrency を見直す
- 問題 signal が少ないので通常設定に戻すことを検討する

This is deliberately opt-in and advice-only. Applications may use the report
for manual operations, logs, dashboards, or their own adaptive controller.

### Observability export helpers

日本語では「監視・ログ基盤へ渡しやすくする変換」です。

FlowBrigade は Prometheus、OpenTelemetry、CloudWatch などの exporter
本体を持ちません。代わりに `MetricEvent` や `ControlReport` を、JSON
line や Prometheus-style text に変換する薄い helper を提供します。

This keeps the core dependency-free while making production adoption easier.
Applications decide whether to write records to logs, metrics collectors,
cloud services, or an in-house pipeline.

`CompoundLimiter` stores rules as `inspect` and `consume` callbacks. This keeps
it independent from concrete limiter types, so in-memory limiters and future
Redis-backed limiters can be combined through the same surface. `consume` first
inspects all rules and consumes only when every rule allows, which avoids
partial consumption in normal single-process use.

`RateLimitStorage` is the adapter boundary for distributed or persistent
limiters. The first supported operation is fixed-window `inspect` and `consume`
for string keys. This matches Redis-style adapters well because the storage
backend can implement `consume` atomically. The core package includes
`InMemoryRateLimitStorage` for tests and single-process use, while Redis,
Memcached, or database adapters should live outside the dependency-free core.
Stored limiters reject blank keys and enforce a maximum key length to reduce
memory abuse when keys are derived from untrusted input. They also reject
control characters in keys and prefixes so storage keys remain safe to log and
inspect. `clear` removes state for one key and is intended for administrative
recovery, not user-facing bypasses.

Storage adapters can be wrapped with `withStorageFailureMode`. `failClosed`
denies when storage is unavailable, while `failOpen` allows and preserves
availability. Stored fixed-window limiters can also receive an audit callback for
application logging or metrics.

The Redis adapter lives in `packages/flowbrigade_redis`. It does not choose a
specific Redis client. Instead it accepts an `EVAL` callback and provides the Lua
scripts needed for atomic fixed-window and token-bucket updates. Lua is used
because Redis executes each script atomically, allowing the adapter to read the
current state, decide, update, set expiry, and return metadata as one Redis
operation.

Async Redis adapters should be added as a parallel adapter surface rather than
changing the synchronous callbacks in place. The core package should remain
dependency-free.

### Internal time source

Public `Clock` belongs to the separate Carbon-style library.

`flowbrigade` may still use an internal time source for deterministic tests and
stable control logic. This should focus on elapsed time and monotonic time, not
calendar time.

This should live under `flowbrigade/internal/time_source.nim` and should not be
marketed as a public feature.

## Proposed source layout

```text
src/
  flowbrigade.nim

  flowbrigade/
    durations.nim
    durations/
      parse.nim
      format.nim
      units.nim
      errors.nim

    backoff.nim
    backoff/
      policies.nim
      jitter.nim

    retry.nim
    retry/
      sync.nim
      errors.nim

    ratelimit.nim
    ratelimit/
      result.nim
      compound.nim
      token_bucket.nim
      fixed_window.nim
      sliding_window.nim
      keyed.nim
      storage.nim

    internal/
      time_source.nim
```

The public entry point should be:

```nim
import pkg/flowbrigade
```

Targeted imports should also work:

```nim
import pkg/flowbrigade/durations
import pkg/flowbrigade/backoff
import pkg/flowbrigade/ratelimit/token_bucket
```

## Proposed test layout

```text
tests/
  test_durations_parse.nim
  test_durations_format.nim
  test_durations_units.nim

  test_backoff_policies.nim
  test_backoff_jitter.nim

  test_retry_sync.nim

  test_ratelimit_token_bucket.nim
  test_ratelimit_fixed_window.nim
  test_ratelimit_keyed.nim
  test_ratelimit_results.nim
  test_ratelimit_sliding_window.nim
  test_ratelimit_compound.nim
  test_ratelimit_storage.nim
```

## TDD order

1. duration parsing
2. duration formatting
3. duration units
4. internal time source
5. backoff policies
6. jitter
7. token bucket
8. fixed window
9. keyed limiter
10. sync retry

The first implementation milestone should focus on duration parsing because it
is pure, easy to specify, and establishes the package's basic style.

## v0.1 scope

- parse compact duration strings
- format durations into compact strings
- fixed, linear, and exponential backoff
- jitter support
- sync retry
- token bucket rate limiter
- fixed window rate limiter
- keyed in-memory limiter
- internal time source for tests

## Later candidates

- async retry
- throttle
- debounce
- circuit breaker
- timeout helpers

These should be added only if they fit the time-control utility concept without
turning the package into a date/time convenience library.
