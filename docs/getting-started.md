# Getting started

This guide is for adding FlowBrigade to an application with the smallest useful
surface first, then growing into storage adapters and operational features when
needed.

## 1. Choose the first use case

Start with one concrete problem:

| Need | Start with |
| --- | --- |
| Retry temporary failures | `apiClientRetryConfig` and `retry` |
| Try secondary providers | `fallback`, `fallbackAsync`, `tryInOrder`, or `tryInOrderAsync` |
| Limit one in-process action | `initTokenBucket` or `initFixedWindow` |
| Limit by user, account, job, or API key | `initKeyedFixedWindow` |
| Track daily or monthly usage quota | `initBudgetLedger` |
| Start from an operational pattern | `loginProtectionPolicy`, `workerBackpressurePolicy`, or another policy builder |
| Review recent control behavior | `analyzeControlSignals` |
| Export metrics to your stack | `toJsonLine`, `toJsonLines`, `toPrometheusLine`, `toPrometheusText`, `controlReportMetrics` |
| Manage several named limits | `LimiterRegistry` |
| Share limits across processes | `StoredFixedWindow` with Redis or another adapter |
| Return HTTP metadata | `rateLimitHeaders` or `httpLimitDecision` |
| Stop calling a failing dependency | `CircuitBreaker` |
| Share one time budget across nested work | `Deadline`, `childDeadline`, `clamp` |
| Limit concurrent in-process work | `Bulkhead` |
| Protect a named critical section | `LockStore`, `withLock`, `refresh`, `inspect` |

Avoid starting with every feature. Add storage, registry, capabilities, and
framework-specific response wiring after the first limiter is working.

Common starting recipes:

- API abuse protection: [../recipes/http_api_abuse_protection.nim](../recipes/http_api_abuse_protection.nim)
- Password reset throttling: [../recipes/password_reset_throttle.nim](../recipes/password_reset_throttle.nim)
- Multi-tenant quotas: [../recipes/multi_tenant_quota.nim](../recipes/multi_tenant_quota.nim)
- Long-running lock leases: [../recipes/lease_refresh.nim](../recipes/lease_refresh.nim)
- Nested time budgets: [../recipes/deadline_composition.nim](../recipes/deadline_composition.nim)

## 2. Install

After publication:

```sh
nimble install flowbrigade
```

Before publication, use the repository locally:

```sh
nim r -p:src tests/all.nim
```

Adapter packages are separate:

```sh
nimble install flowbrigade_redis
nimble install flowbrigade_ready
nimble install flowbrigade_memcached
```

## 3. Add a first limiter

```nim
import flowbrigade

var limiter = initKeyedFixedWindow[string](
  limit = 5,
  per = 1.min,
  maxKeys = 10_000
)

let decision = limiter.consume("account:42:login")
if not decision.allowed:
  raiseIfDenied(decision)
```

For HTTP-facing code, keep FlowBrigade independent from the framework response
type:

```nim
let http = httpLimitDecision(decision)
if not http.allowed:
  discard http.statusCode
  discard http.headers
  discard http.body
```

## 4. Start from a policy bundle when the pattern is common

Policy builders create a small named registry plus related configs. Use them
when the pattern is already known, such as login protection, API abuse
protection, worker backpressure, third-party API calls, or tenant quotas:

```nim
import flowbrigade

let policy = loginProtectionPolicy(accountLimit = 5, accountWindow = 15.min)
let decision = policy.consume("account:42")
```

Policy bundles are still plain FlowBrigade parts. You can inspect their
registry, merge their limiters into your own registry, or initialize optional
objects such as circuit breakers and bulkheads when the policy includes them.

## 5. Move repeated rules into a registry

```nim
import flowbrigade

var registry = initLimiterRegistry()
registry.addLimiter("login", keyedFixedWindowDefinition(limit = 5, per = 1.min))
registry.addLimiter("account", keyedFixedWindowDefinition(limit = 20, per = 1.hr))
registry.addCompoundLimiter("login_guard", ["login", "account"])

let decision = registry.consume("login_guard", key = "account:42")
```

Use a registry when limits are configured by name or shared by several modules.
Use direct limiter objects when one module owns one simple limiter.

## 6. Add fallback when another provider is acceptable

Use fallback when a secondary provider, cached path, or degraded implementation
is acceptable after a primary failure. Sync and async variants have the same
meaning:

```nim
import flowbrigade

let value = fallback(
  primary = proc(): string =
    raise newException(IOError, "primary failed"),
  secondary = proc(): string =
    "cached result"
)
```

`tryInOrder` returns metadata such as the provider that succeeded and the
providers that failed. `tryInOrderAsync` does the same for async providers.
Providers can also be guarded by a `CircuitBreaker`, so an open circuit is
skipped before the provider is called.

## 7. Add quota when usage must accumulate

Use rate limiters for short-term flow. Use a budget ledger when a tenant, API
key, job type, or worker has a fixed allowance for a longer period:

```nim
import flowbrigade

var quota = initBudgetLedger(monthlyQuotaConfig(100_000))

let decision = quota.consume("tenant:42", cost = 250)
if not decision.allowed:
  discard decision.resetAfter
```

Budget keys are trimmed and validated. Prefer opaque keys when the source value
contains personal data, account identifiers, or secrets.

## 8. Build keys deliberately

Use `rateLimitKey` when parts are already strings:

```nim
let key = rateLimitKey(["account", "42", "login"])
```

Use `KeyExtractor` when application request data has to be converted:

```nim
type LoginAttempt = object
  accountId: string
  action: string

let extractor = initKeyExtractor[LoginAttempt]()
  .withPart(proc(input: LoginAttempt): string = input.accountId)
  .withPart(proc(input: LoginAttempt): string = input.action)

let key = extractor.extract(LoginAttempt(accountId: "42", action: "login"))
```

Use `opaqueRateLimitKey` with a vetted application-provided fingerprint when raw
keys contain personal data or secrets.

## 9. Choose storage only when needed

Use in-process limiters for:

- CLIs
- one-process tools
- tests
- local worker throttling

Use storage-backed limiters when limits must be shared across:

- processes
- service replicas
- machines
- deployments behind a load balancer

Redis is the first supported distributed adapter. Memcached support is
experimental because it depends on real `gets`/`cas` behavior from the chosen
client.

Check adapter guarantees explicitly:

```nim
let capabilities = redisRateLimitCapabilities()
capabilities.requireCapabilities([rlcInspect, rlcAtomicConsume, rlcDistributed])
```

## 10. Decide storage failure behavior

External stores can fail. Choose the behavior explicitly:

```nim
let protectedStorage = storage.withStorageFailureMode(failClosed)
```

Use `failClosed` when bypassing the limit is dangerous, such as login or abuse
protection. Use `failOpen` when availability matters more than the limit, such
as non-critical telemetry throttling.

## 11. Add observability

FlowBrigade does not choose a metrics or logging package. Convert events into a
simple shape and forward them to your stack:

```nim
let metric = metricEvent(deniedResult(
  limit = 10,
  remaining = 0,
  retryAfter = 30.sec,
  resetAfter = 1.min
))
```

Stored limiters can also emit audit events through the `audit` callback.
Budget decisions and events also convert through `metricEvent`.

To hand records to your logging or metrics stack, convert them to simple
dependency-free shapes:

```nim
let event = metricEvent(deniedResult(
  limit = 10,
  remaining = 0,
  retryAfter = 30.sec,
  resetAfter = 1.min
))

let jsonLine = event.toJsonLine()
let textLine = event.toPrometheusLine()
```

FlowBrigade does not run exporters or background agents. Your application owns
where these lines go.

## 12. Diagnose control pressure without automatic changes

Control diagnostics are opt-in. They analyze signals that your application
chooses to record and return advice-only hints. FlowBrigade does not change
retry counts, rate limits, circuit breakers, bulkheads, or timeouts for you.

```nim
import flowbrigade

let report = analyzeControlSignals(@[
  failureSignal(),
  timeoutSignal(),
  successSignal(25.ms)
], ControlDiagnosticsConfig(minSignals: 3))

for hint in report.hints:
  discard hint.kind
```

Use the report for manual review, logs, dashboards, or an application-owned
adaptive controller.

## 13. Verify locally

Run core tests:

```sh
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim test
```

Check snippets and dependency-free recipes:

```sh
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim snippets
```

For Redis and Memcached integration tests, see
[local-services.md](local-services.md). Tests print `SKIP:` with a reason when
the local service is unavailable.

## 14. Production checklist

- Validate limiter keys before sending them to external storage.
- Prefer opaque keys for user identifiers or other sensitive values.
- Set `maxKeys` for keyed in-memory limiters receiving untrusted input.
- Use shared storage when limits must apply across processes.
- Confirm adapter capabilities before relying on distributed behavior.
- Choose `failOpen` or `failClosed` deliberately.
- Use fallback only for operations where a secondary result is semantically
  acceptable.
- Surface `Retry-After` or equivalent wait metadata to callers.
- Use budgets for longer usage allowances instead of stretching short-window
  rate limits.
- Treat control diagnostics as advice unless your application explicitly opts
  into applying a hint.
- Pass deadlines downward when multiple operations share one caller-visible
  time budget.
- Use lease-token lock release when coordinating critical sections.
- Refresh long-running lock leases before their TTL expires, and reject stale
  tokens in external adapters.
- Keep authentication, authorization, encryption, and service hardening outside
  FlowBrigade unless an adapter explicitly owns that boundary.
