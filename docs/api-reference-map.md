# API reference map

Use this page as a map to the public API surface. Full behavior should stay in
API docs, tests, and recipes rather than being duplicated here.

## Core import

- `pkg/flowbrigade`: aggregate import for the dependency-free core package.

## Presets and configuration

- `pkg/flowbrigade/config`
- `RetryConfig`, `TokenBucketConfig`, `FixedWindowConfig`,
  `SlidingWindowConfig`, `KeyedFixedWindowConfig`, `BudgetConfig`,
  `CircuitBreakerConfig`:
  plain configuration objects suitable for values loaded by other libraries.
- `initRetryConfig`, `initTokenBucketConfig`, `initFixedWindowConfig`,
  `initSlidingWindowConfig`, `initKeyedFixedWindowConfig`, `initBudgetConfig`,
  `initCircuitBreakerConfig`: validated config constructors.
- `initTokenBucket(config)`, `initFixedWindow(config)`,
  `initSlidingWindow(config)`, `initKeyedFixedWindow[T](config)`,
  `initBudgetLedger(config)`, `initCircuitBreaker(config)`: build runtime
  objects from config.
- `pkg/flowbrigade/presets`
- `apiClientRetryPolicy`, `workerRetryPolicy`: common backoff policies.
- `apiClientRetryConfig`, `workerRetryConfig`: retry configs with attempts.
- `strictRateLimitConfig`, `lenientRateLimitConfig`, `dailyQuotaConfig`,
  `monthlyQuotaConfig`,
  `strictCircuitBreakerConfig`: common starting points that callers can
  override.

## Policy builders

- `pkg/flowbrigade/policy`
- `FlowPolicy`: small bundle containing a named limiter registry plus optional
  quota, retry, circuit-breaker, and bulkhead configuration.
- `apiAbuseProtectionPolicy`: per-identity limiter plus global burst limiter.
- `loginProtectionPolicy`: account and identity guard limiters.
- `passwordResetProtectionPolicy`: stricter account and identity limiters.
- `thirdPartyApiClientPolicy`: token bucket plus retry and circuit-breaker
  config.
- `workerBackpressurePolicy`: token bucket plus worker retry, circuit-breaker,
  and bulkhead config.
- `multiTenantQuotaPolicy`: burst limiter plus longer-period budget config.
- `consume`, `inspect`, `allow`: use the policy's primary limiter.
- `initBudgetLedger(policy)`, `initCircuitBreaker(policy)`,
  `initBulkhead(policy)`: initialize optional runtime objects when present.
- `mergeInto`: copy policy limiters into a caller-owned registry.

## Control diagnostics

- `pkg/flowbrigade/control_diagnostics`
- `ControlSignal`: caller-provided success, failure, timeout, rate-limit,
  circuit-open, or bulkhead-full observation.
- `ControlDiagnosticsConfig`: thresholds and minimum sample size.
- `analyzeControlSignals`: returns an advice-only `ControlReport`.
- `ControlReport`: aggregate rates, average latency, and hints.
- `ControlHint`: an explicit suggestion such as inspect downstream, reduce
  retry attempts, tighten rate limit, reduce concurrency, increase capacity, or
  restore normal settings. FlowBrigade does not apply hints automatically.

## Observability export

- `pkg/flowbrigade/observability`
- `ObservationRecord`: simple name/value/attributes shape for application-owned
  exporters.
- `toObservationRecord`: convert `MetricEvent`.
- `toJson` and `toJsonLine`: convert metric records to JSON for logs or queues.
- `toPrometheusLine`: produce Prometheus-style text lines without running an
  exporter.
- `controlReportToJson` and `controlReportToJsonLine`: serialize advice-only
  control diagnostics.
- `controlReportMetrics`: expose control report rates and hints as
  `MetricEvent` values.
- `sanitizeMetricName` and `sanitizeAttributeKey`: normalize names for text
  output.

## Duration

- `pkg/flowbrigade/durations`
- `parseDuration`: parse compact strings such as `250ms`, `30s`, and `1h30m`.
- `formatDuration`: format a Nim `Duration` as compact text.
- `ns`, `us`, `ms`, `sec`, `min`, `hr`, `day`: duration unit helpers.

## Backoff

- `pkg/flowbrigade/backoff`
- `fixedBackoff`: same delay for each retry.
- `linearBackoff`: grows by a fixed step.
- `expBackoff`: grows by a factor with optional maximum delay.
- `delayFor`: returns the delay for an attempt.
- `noJitter`, `fullJitter`, `equalJitter`, `decorrelatedJitter`: jitter modes.

## Retry

- `pkg/flowbrigade/retry`
- `retry`: synchronous retry.
- `retryAsync`: asynchronous retry for futures.
- `SleepProc`: caller-provided sleep hook.
- `RetryObserverProc` and `RetryEvent`: observe failures, sleeps, exhaustion,
  and success without coupling to a logging library.

## Fallback

- `pkg/flowbrigade/fallback`
- `fallback`: try primary, then secondary when the predicate allows fallback.
- `fallbackAsync`: async version of `fallback`.
- `tryInOrder`: try named providers in order and return `FallbackResult`.
- `tryInOrderAsync`: async version of `tryInOrder`.
- `fallbackProvider`: build named providers, optionally guarded by a
  `CircuitBreaker`.
- `asyncFallbackProvider`: build named async providers, optionally guarded by a
  `CircuitBreaker`.
- `FallbackResult`: value, selected provider, attempts, failed providers, and
  last error metadata.
- `FallbackObserverProc` and `FallbackEvent`: observe attempts, failures,
  successes, and circuit-skip events.
- `FallbackError`: raised when every provider fails.

## Rate limiting

- `pkg/flowbrigade/ratelimit`
- `initTokenBucket`: burst-friendly limiter with refill.
- `initFixedWindow`: simple fixed-period counter.
- `initSlidingWindow`: weighted previous/current window limiter.
- `initKeyedFixedWindow`: in-memory per-key fixed window.
- `initCompoundLimiter`: combine multiple limiter rules.
- `RateLimitResult`: decision metadata for allow/deny, remaining quota, retry
  delay, and reset delay.
- `inspect`: check without consuming capacity.
- `consume`: check and consume capacity.
- `allow`: boolean convenience wrapper around `consume`.
- `rateLimitHeaders` and `retryAfterSeconds`: HTTP response metadata helpers.
- `httpLimitDecision`: framework-neutral HTTP status/body/header data.
- `RateLimitExceededError`, `raiseIfDenied`, `remainingOrRaise`: typed
  exception helpers for denied decisions.
- `wait` and `waitAsync`: pause until the decision can be retried.
- `rateLimitKey` and `opaqueRateLimitKey`: validated key builders.
- `RateLimitStorage` and `AsyncRateLimitStorage`: adapter callback surfaces.
- `RateLimitCapabilities`, `supports`, `requireCapability`,
  `requireCapabilities`: describe and enforce adapter guarantees.
- `initStoredFixedWindow`: fixed-window limiter backed by storage callbacks.
- `initInMemoryRateLimitStorage`: bounded in-process storage for tests and
  single-process tools.
- `withStorageFailureMode`: choose fail-open or fail-closed behavior when
  storage throws.
- `StoredFixedWindowAuditProc`: observe stored limiter inspect, consume, and
  clear operations.
- `parseRateLimitRate`: parse compact rate expressions such as `100/m`,
  `5-S`, and `1000/1h`.
- `KeyExtractor[T]`: build validated keys from caller-defined input shapes.
- `LimiterRegistry`: register named limiter handles or definitions.
- `fixedWindowDefinition`, `slidingWindowDefinition`,
  `tokenBucketDefinition`, `keyedFixedWindowDefinition`: definitions for named
  registry construction.
- `addStoredFixedWindow`: attach a storage-backed limiter to a registry.
- `addCompoundLimiter`: compose named limiters without duplicating state.
- `reserve`, `RateLimitReservation`, `raiseIfRejected`: build a waitable
  reservation shape from a decision. The default `maxWait` means no max wait.
  Strict distributed future-capacity reservation should be advertised by
  adapters with `rlcReservation`.

## Budgets and quotas

- `pkg/flowbrigade/budget`
- `initBudgetLedger`: in-memory per-key usage budget for a fixed period.
- `BudgetResult`: decision metadata for allow/deny, used amount, remaining
  amount, retry delay, and reset delay.
- `inspect`: check whether a cost fits without consuming budget.
- `consume`: check and consume budget.
- `allow`: boolean convenience wrapper around `consume`.
- `refund`: return usage to the current period, clamped at zero.
- `reset` and `resetAll`: clear usage for one key or every key.
- `BudgetEvent`: observer-friendly event shape for budget inspect, consume,
  refund, and reset operations.

## Traffic shaping

- `pkg/flowbrigade/throttle`: allow an action at most once per interval.
- `pkg/flowbrigade/debounce`: wait until repeated calls go quiet.
- `pkg/flowbrigade/circuit_breaker`: stop calling failing dependencies and
  emit circuit observer events.
- `pkg/flowbrigade/timeout`: track elapsed time, remaining time, and deadline
  propagation through `Deadline`, `childDeadline`, `clamp`, and `toTimeout`.
- `pkg/flowbrigade/bulkhead`: limit concurrent in-process work with explicit
  acquire/release or `withBulkhead`.
- `pkg/flowbrigade/locks`: framework-neutral lock store contract with
  lease-token release, lease refresh, lease inspection, in-memory
  test/single-process storage, and `withLock`.
- `pkg/flowbrigade/thread_safe`: process-local mutex wrappers for sharing
  in-memory `FlowPolicy` and `LimiterRegistry` instances across threads.

## Observability

- `pkg/flowbrigade/metrics`
- `MetricEvent`: simple name/tags/value event shape.
- `metricEvent`: convert retry events, circuit breaker events, stored
  fixed-window audit events, rate-limit decisions, budget decisions, and budget
  events to `MetricEvent`.
- `pkg/flowbrigade/observability`: convert metric events and control reports to
  observation records, JSON lines, and Prometheus-style text.

## Adapter packages

- `flowbrigade_redis`: Redis fixed-window and token-bucket adapter primitives.
- `flowbrigade_ready`: bridge for the `ready` Redis client.
- `flowbrigade_memcached`: experimental Memcached fixed-window adapter.
- `flowbrigade_prologue`: experimental Prologue middleware bridge with
  rate-limit middleware, login/password-reset guards, deadline middleware,
  method-scoped limits, request key helpers, compound key extraction, and
  INI-style config file helpers.

## C ABI

- `src/flowbrigade_c.nim`: experimental C ABI implementation.
- `include/flowbrigade.h`: C declarations for duration, token bucket, fixed
  window, and circuit breaker bindings.
