# flowbrigade

Flow control utilities for Nim.

`flowbrigade` is a small library for flow control: duration parsing, retry
policies, rate limiting, quotas, throttling, debouncing, circuit breaking,
timeouts, and bulkheads. It is useful for API clients, CLIs, workers, batch
jobs, and web services, but it is not web-specific.

This is not a Carbon-like date/time convenience library. It does not handle
timezones, calendar math, date formatting, localization, or relative display
text such as "3 minutes ago".

## Project Status

The core package is dependency-free and is intended to be usable before 1.0.
Public APIs are documented in [docs/api-stability.md](docs/api-stability.md).
Supported and experimental areas are listed in
[docs/support-matrix.md](docs/support-matrix.md).

## Quick Start

```nim
import pkg/flowbrigade

let retryConfig = apiClientRetryConfig()

var limiter = initTokenBucket(rate = 10, per = 1.sec, burst = 20)
if limiter.allow():
  discard retry(
    policy = retryConfig.policy,
    maxAttempts = retryConfig.maxAttempts,
    operation = proc(): string = "ok"
  )
```

## Features

- Parse compact duration strings such as `250ms`, `30s`, and `1h30m`
- Format Nim `Duration` values into compact strings
- Build fixed, linear, and exponential retry delays
- Add jitter to avoid synchronized retries
- Retry synchronous operations
- Retry asynchronous operations
- Fall back to secondary providers in a controlled order, sync or async
- Limit repeated actions with token bucket and fixed window limiters
- Limit actions per key with an in-memory keyed fixed window limiter
- Track per-key usage budgets and quotas over fixed periods
- Throttle repeated actions
- Debounce bursts of repeated signals
- Stop calling failing operations with a circuit breaker
- Track simple timeouts, deadlines, and remaining time
- Limit concurrent work with a bulkhead
- Build common policies from config objects or presets
- Start from practical policy bundles for login, API abuse, API clients,
  workers, and tenant quotas
- Analyze recent control signals and return opt-in policy hints without
  changing settings automatically
- Convert metrics and control reports into JSON lines or Prometheus-style text
  for application-owned observability pipelines
- Register and use named limiters through a registry
- Extract validated keys from application-specific request shapes
- Parse compact rate strings such as `100/m` and `1000/1h`
- Describe adapter guarantees with capability sets
- Convert denied rate-limit decisions into waitable reservations
- Coordinate single-process work with lock stores and refresh long-running
  leases
- Convert observer events into simple metric events
- Raise typed errors from denied rate-limit decisions
- Use sync or async storage-backed fixed-window rate limiting
- Use separate Redis, Memcached, and client bridge packages when distributed
  state is needed
- Build the experimental C ABI layer for non-Nim bindings

## When To Use What

| Need | Use |
| --- | --- |
| Parse `30s` or `1h30m` from config | `parseDuration` |
| Retry temporary failures | `retry` or `retryAsync` with `BackoffPolicy` |
| Try secondary providers after a failure | `fallback`, `fallbackAsync`, `tryInOrder`, or `tryInOrderAsync` |
| Allow short bursts with steady refill | `TokenBucket` |
| Enforce short-term request flow | `FixedWindow` or `StoredFixedWindow` |
| Track usage quota or budget per tenant/API key | `BudgetLedger` |
| Smooth boundary spikes | `SlidingWindow` |
| Limit per user/API key/job | `KeyedFixedWindow` or stored fixed-window keys |
| Combine global and per-key limits | `CompoundLimiter` |
| Manage configured named limits | `LimiterRegistry` |
| Build keys from app request data | `KeyExtractor` |
| Convert compact rate config | `parseRateLimitRate` |
| Check adapter guarantees | `RateLimitCapabilities` |
| Wait when a denial is acceptable | `reserve` and `RateLimitReservation` |
| Return HTTP metadata | `rateLimitHeaders` |
| Build framework-neutral HTTP decisions | `httpLimitDecision` |
| Raise on denial | `raiseIfDenied` or `remainingOrRaise` |
| Share limits across processes | `flowbrigade_redis` or a storage adapter |
| Stop calling a failing dependency | `CircuitBreaker` |
| Limit concurrent in-process work | `Bulkhead` |
| Share an overall time budget across nested work | `Deadline`, `childDeadline`, `clamp` |
| Coordinate named critical sections | `LockStore`, `withLock`, `refresh`, `inspect` |
| Drop repeated actions until quiet | `Debouncer` |
| Start from common defaults | `apiClientRetryConfig`, `workerRetryConfig`, presets |
| Start from complete operational patterns | `loginProtectionPolicy`, `apiAbuseProtectionPolicy`, `workerBackpressurePolicy` |
| Diagnose whether controls need adjustment | `analyzeControlSignals` |
| Connect to logging or metrics | Observer hooks plus `metricEvent`, `toJsonLine`, `toJsonLines`, `toPrometheusLine`, `toPrometheusText` |

## Quotas And Budgets

Budgets track how much a key has used in a fixed period. Use them for tenant
quotas, API-key allowances, monthly job budgets, or token/cost ceilings.

```nim
import pkg/flowbrigade

var quota = initBudgetLedger(dailyQuotaConfig(1_000))

let decision = quota.consume("tenant:acme", cost = 250)
if not decision.allowed:
  echo "quota resets after ", formatDuration(decision.resetAfter)
```

Rate limiters answer "is this burst allowed right now?". Budgets answer "how
much of this period's allowance is left?".

## Install

This package is intended to be installed with Nimble after publication:

```sh
nimble install flowbrigade
```

For local development, compile tests with the local `src` path:

```sh
nim r -p:src tests/all.nim
```

Adapter packages are published separately:

- `flowbrigade_redis`
- `flowbrigade_ready`
- `flowbrigade_memcached`
- `flowbrigade_prologue`

For a step-by-step adoption path, see
[docs/getting-started.md](docs/getting-started.md). For project readiness
checks, see [docs/adoption-checklist.md](docs/adoption-checklist.md).
For Prologue applications, see
[docs/integrations-prologue.md](docs/integrations-prologue.md).

## Recipes

Compile-checked recipes live in [recipes/](recipes/):

- [API client retry](recipes/api_client_retry.nim)
- [Login rate limit](recipes/login_rate_limit.nim)
- [Worker backpressure](recipes/worker_backpressure.nim)
- [Failure modes](recipes/failure_modes.nim)
- [Observability hooks](recipes/observability_hooks.nim)
- [Named limiters](recipes/named_limiters.nim)
- [HTTP API abuse protection](recipes/http_api_abuse_protection.nim)
- [Password reset throttle](recipes/password_reset_throttle.nim)
- [Multi-tenant quota](recipes/multi_tenant_quota.nim)
- [Policy builder](recipes/policy_builder.nim)
- [Control diagnostics](recipes/control_diagnostics.nim)
- [Observability export](recipes/observability_export.nim)
- [Fallback API client](recipes/fallback_api_client.nim)
- [Async fallback API client](recipes/async_fallback_api_client.nim)
- [Lease refresh](recipes/lease_refresh.nim)
- [Deadline composition](recipes/deadline_composition.nim)
- [Service guard pipeline](recipes/service_guard_pipeline.nim)
- [Redis distributed limit](recipes/redis_distributed_limit.nim)

## Duration Parsing

```nim
import pkg/flowbrigade

let timeout = parseDuration("30s")
let interval = parseDuration("1h30m")

echo formatDuration(interval) # 1h30m
```

Accepted units:

- `ns`
- `us`
- `ms`
- `s`
- `m`
- `h`
- `d`

`d` is a fixed 24-hour period. Calendar units such as months and years are not
accepted.

Whitespace may appear between values and units, and a single leading sign is
accepted:

```nim
check parseDuration("1 h 30 m") == parseDuration("1h30m")
check parseDuration("-1h30m") == -parseDuration("1h30m")
```

Embedded signs such as `1h-30m` are rejected.

## Backoff

Backoff means the rule for how long to wait after a failure before trying again.

```nim
import std/times
import pkg/flowbrigade

let policy = expBackoff(
  initial = initDuration(milliseconds = 100),
  factor = 2.0,
  maxDelay = initDuration(seconds = 5),
  jitter = fullJitter
)

echo policy.delayFor(attempt = 1) # around 0ms..100ms with full jitter
echo policy.delayFor(attempt = 2) # around 0ms..200ms with full jitter
```

Available policy constructors:

- `fixedBackoff`
- `linearBackoff`
- `expBackoff`

For exponential backoff, `factor` must be greater than `1.0`.

Available jitter modes:

- `noJitter`
- `fullJitter`
- `equalJitter`
- `decorrelatedJitter`

## Retry

Retry runs an operation multiple times until it succeeds or attempts are
exhausted.

```nim
import std/times
import pkg/flowbrigade

let policy = fixedBackoff(initDuration(milliseconds = 100))

proc sleep(delay: Duration) =
  # Replace this with the sleep function that fits your application.
  discard

proc callService(): int =
  42

let result = retry(
  policy = policy,
  maxAttempts = 3,
  sleep = sleep,
  operation = callService
)
```

Retrying is not always safe. The caller must decide whether running the same
operation more than once is acceptable, especially for side-effecting actions
such as payments, writes, or email delivery.

Async retry is available as `retryAsync` for operations that return futures.

For simple blocking usage, `retry` also has an overload that uses FlowBrigade's
default sleep helper:

```nim
let result = retry(
  policy = policy,
  maxAttempts = 3,
  operation = callService
)
```

## Rate Limiting

Rate limiting controls how many times an action may run in a period.

```nim
import std/times
import pkg/flowbrigade

var limiter = initTokenBucket(
  rate = 10,
  per = initDuration(seconds = 1),
  burst = 20
)

if limiter.allow():
  discard
```

Use `consume` when callers need response metadata such as remaining capacity or
how long to wait before retrying:

```nim
let result = limiter.consume()

if not result.allowed:
  echo "retry after ", result.retryAfter
```

Use `inspect` to check the current decision without consuming capacity.
Use `rateLimitHeaders` to expose HTTP response metadata such as
`RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`, and `Retry-After`.
Use `wait` or `waitAsync` when a caller should pause until retrying instead of
dropping work immediately.

Tests can use the internal manual time source to avoid waiting in real time. A
public date/time `Clock` API is intentionally out of scope for this package.

For keyed in-memory limiters, configure `maxKeys` when keys come from untrusted
input such as IP addresses or request parameters. Expired entries are pruned, and
new keys are rejected when the configured key capacity is still full.

Available limiter styles:

- `TokenBucket`: allows bursts while refilling capacity over time
- `FixedWindow`: simple counter per fixed time window
- `SlidingWindow`: smooths fixed-window boundary spikes by weighting the
  previous window
- `KeyedFixedWindow`: tracks a fixed window independently per key
- `CompoundLimiter`: combines multiple limiter rules and allows only when every
  rule allows

```nim
var globalLimit = initFixedWindow(
  limit = 1000,
  per = initDuration(minutes = 1)
)
var burstLimit = initTokenBucket(
  rate = 10,
  per = initDuration(seconds = 1),
  burst = 20
)

let limiter = initCompoundLimiter([
  rateLimitRule(
    "global",
    proc(): RateLimitResult = globalLimit.inspect(),
    proc(): RateLimitResult = globalLimit.consume()
  ),
  rateLimitRule(
    "burst",
    proc(): RateLimitResult = burstLimit.inspect(),
    proc(): RateLimitResult = burstLimit.consume()
  )
])
```

External storage adapters can use `RateLimitStorage` and `StoredFixedWindow`.
The core package includes an in-memory implementation for tests and
single-process use:

```nim
let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
let limiter = initStoredFixedWindow(
  prefix = "api",
  limit = 100,
  per = initDuration(minutes = 1),
  storage = storage
)

discard limiter.consume("user:42")
```

Redis or Memcached adapters implement the same storage callbacks without adding
those dependencies to the core package.

Adapter packages are kept under `packages/` so the core package remains
dependency-free:

- `packages/flowbrigade_redis`: Redis fixed-window and token-bucket adapter
- `packages/flowbrigade_ready`: bridge for the `ready` Redis client
- `packages/flowbrigade_memcached`: experimental Memcached fixed-window adapter

FlowBrigade intentionally does not provide a generic cache abstraction. Rate
limiting needs atomic consume behavior, non-consuming inspect, TTL/window
rollover, and retry metadata. Backend adapters must prove those semantics
directly.

When limiter keys come from untrusted input, keep them short and stable. Stored
limiters reject blank keys and limit key length with `maxKeyLength`, which
defaults to 512 bytes. Stored limiters also reject control characters in keys
and prefixes.

Use `clear` to remove a stored fixed-window state for operational recovery, such
as unblocking a user after a false positive:

```nim
discard limiter.clear("user:42")
```

Use `rateLimitKey` to build validated keys from stable parts:

```nim
let key = rateLimitKey(["user", "42", "login"])
```

Use `opaqueRateLimitKey` when the original identifier should not be stored or
logged directly. The fingerprint function is provided by the application so it
can use its preferred hash or HMAC implementation.

Wrap external storage with `withStorageFailureMode` to choose how the limiter
behaves when Redis or another backend is unavailable:

```nim
let storage = redisStorage
  .asRateLimitStorage()
  .withStorageFailureMode(failClosed)
```

Use `audit` on stored limiters to observe inspect, consume, and clear decisions
without tying FlowBrigade to a specific logging or metrics stack.

## Adapter Selection

Use the core package for in-process control. Use adapter packages only when
state must be shared across processes or machines.

```nim
import std/times
import ready
import pkg/flowbrigade/ratelimit
import pkg/flowbrigade_ready

let conn = newRedisConn("127.0.0.1", Port(6379))
let redisStorage = initReadyRateLimitStorage(conn)
let limiter = initStoredFixedWindow(
  prefix = "api",
  limit = 100,
  per = initDuration(minutes = 1),
  storage = redisStorage.asRateLimitStorage()
)
```

See [docs/adapter-selection.md](docs/adapter-selection.md) for provider
selection rules and supported combinations.

## Throttle

Throttle allows an action at most once per interval.

```nim
import std/times
import pkg/flowbrigade

var throttle = initThrottle(every = initDuration(seconds = 1))

if throttle.allow():
  discard
```

## Debounce

Debounce waits until repeated calls have gone quiet for a delay.

```nim
import std/times
import pkg/flowbrigade

var debouncer = initDebouncer(delay = initDuration(milliseconds = 250))

debouncer.call()

if debouncer.consumeReady():
  discard
```

## Circuit Breaker

A circuit breaker stops calling an operation after repeated failures, then lets
one trial through after a reset delay.

```nim
import std/times
import pkg/flowbrigade

var breaker = initCircuitBreaker(
  failureThreshold = 3,
  resetAfter = initDuration(seconds = 30)
)

if breaker.allow():
  try:
    discard
    breaker.recordSuccess()
  except CatchableError:
    breaker.recordFailure()
```

## Timeout And Deadline

Timeout tracks whether a duration has elapsed and how much time remains.
Deadline tracks an absolute monotonic cutoff so nested operations can share the
same total time budget.

```nim
import std/times
import pkg/flowbrigade

let timeout = initTimeout(after = initDuration(seconds = 5))

if timeout.expired():
  discard

let requestDeadline = initDeadline(after = initDuration(seconds = 3))
let databaseDeadline = requestDeadline.childDeadline(initDuration(seconds = 1))
let downstreamTimeout = databaseDeadline.toTimeout()

discard downstreamTimeout
```

## Experimental C ABI

FlowBrigade also exposes an experimental C ABI for small bindings in languages
such as Zig, Odin, Rust, C, and C++.

The current ABI covers:

- duration parsing and formatting
- fixed, linear, and exponential backoff delay calculation
- token bucket, fixed window, and sliding window rate limiters
- circuit breaker state transitions
- bulkhead permit tracking
- timeout/deadline checks and remaining-time helpers
- budget ledger quota checks, refunds, and resets
- in-memory lock stores with opaque lease handles
- throttle and debounce state handles
- retry execution with C operation and sleep callbacks
- fallback execution with ordered C provider callbacks
- named limiter registry operations, including C callback storage-backed fixed
  windows
- rate-limit and budget result export to JSON lines or Prometheus-style text
- ABI feature checks for bindings

Build the shared library:

```sh
nimble cabi
```

The C declarations live in [include/flowbrigade.h](include/flowbrigade.h).
Call `NimMain()` once before calling `fb_*` functions from a non-Nim host
process. The ABI uses opaque handles, caller-owned buffers, fixed structs, and
integer status codes; Nim exceptions do not cross the boundary. Use
`fb_abi_version()` for compatibility checks and `fb_last_error()` for diagnostic
text after a failed ABI call.

See [docs/c-abi.md](docs/c-abi.md) for details and
[docs/spec.md](docs/spec.md) for the language-neutral behavior model.

## Module Layout

Most users can import everything:

```nim
import pkg/flowbrigade
```

Focused imports are also supported:

```nim
import pkg/flowbrigade/durations
import pkg/flowbrigade/backoff
import pkg/flowbrigade/ratelimit
import pkg/flowbrigade/circuit_breaker
import pkg/flowbrigade/throttle
import pkg/flowbrigade/debounce
import pkg/flowbrigade/timeout
```

## Development

Run all tests:

```sh
nim r --nimcache:/tmp/flowbrigade-nimcache -p:src tests/all.nim
```

Nimble task:

```sh
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim test
```

The explicit `--nim` flag is only needed in environments where Nimble cannot
discover the active Nim binary.

Check the public entry point:

```sh
nim check --nimcache:/tmp/flowbrigade-nimcache -p:src src/flowbrigade.nim
```

Build docs:

```sh
nim doc --nimcache:/tmp/flowbrigade-nimcache -p:src --outdir:/tmp/flowbrigade-docs src/flowbrigade.nim
```

Run benchmark smoke tests:

```sh
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim benchmark
```

Check README snippets and dependency-free recipes:

```sh
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim snippets
```

See [docs/design.md](docs/design.md) for design notes.
See [docs/getting-started.md](docs/getting-started.md) for a step-by-step adoption guide.
See [docs/adoption-checklist.md](docs/adoption-checklist.md) for integration readiness checks.
See [docs/api-reference-map.md](docs/api-reference-map.md) for the public API map.
See [docs/test-matrix.md](docs/test-matrix.md) for the current test coverage map.
See [docs/support-matrix.md](docs/support-matrix.md) for supported areas.
See [docs/api-stability.md](docs/api-stability.md) for compatibility policy.
See [docs/local-services.md](docs/local-services.md) for local Redis and Memcached verification.
See [docs/c-abi.md](docs/c-abi.md) for the experimental C ABI surface.
See [docs/release-checklist.md](docs/release-checklist.md) before publishing.
See [SECURITY.md](SECURITY.md) for security scope and operational limits.
