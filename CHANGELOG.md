# Changelog

FlowBrigade is not published yet. This changelog records notable pre-release
work so the first public release has a clear history.

## Unreleased

- Added duration parsing, formatting, and unit helpers.
- Added fixed, linear, and exponential backoff policies.
- Added jitter modes.
- Added sync and async retry helpers.
- Added retry observer hooks and default sleep helpers.
- Added fallback helpers for ordered secondary-provider execution with
  observer events and optional circuit-breaker guards.
- Added async fallback helpers with the same ordered-provider semantics.
- Added token bucket, fixed window, sliding window, keyed fixed window, and
  compound rate limiters.
- Added rate-limit result metadata and non-consuming `inspect`.
- Added HTTP rate-limit header helpers.
- Added sync and async wait helpers.
- Added validated rate-limit key builders.
- Added storage-backed fixed-window limiters.
- Added sync and async storage adapter surfaces.
- Added in-memory storage adapter.
- Added Redis adapter package with fixed-window and token-bucket support.
- Added `ready` Redis client bridge.
- Added Memcached fixed-window adapter package as experimental.
- Added experimental Prologue framework bridge package with rate-limit
  middleware and request key helpers.
- Added Prologue login/password-reset guard helpers, deadline helpers, and
  framework-specific examples.
- Expanded the Prologue bridge with query/path/cookie/form key helpers,
  compound key extraction, method-scoped middleware, custom denied content
  type support, disabled-header coverage, and thread-safe policy middleware
  tests.
- Added Prologue INI-style config helpers for constructing API abuse and login
  middleware from application configuration.
- Added thread-safe in-process wrappers for sharing FlowBrigade policies and
  limiter registries across multi-threaded framework handlers.
- Removed the planned Jester bridge from the release scope because upstream
  Jester/httpbeast has known Nim 2 multi-thread runtime risk.
- Added throttle, debounce, circuit breaker, timeout helpers, and observer
  hooks.
- Added security policy, adapter policy, support matrix, benchmarks, examples,
  and release checklist.
- Added compile-checked recipes and README snippets.
- Added failure-mode and observability recipes.
- Added local service verification notes and a public API reference map.
- Added policy presets and plain config objects for common construction paths.
- Added metric event conversion helpers for observer and audit events.
- Added in-process bulkhead concurrency limiter.
- Added typed rate-limit denial exception helpers.
- Added named limiter registry, compact rate parser, key extractor, and
  framework-neutral HTTP decision helpers.
- Added adapter capability contracts, waitable rate-limit reservations, and a
  framework-neutral lock store contract.
- Added per-key budget/quota ledger with config presets, metric conversion,
  tests, and a multi-tenant quota recipe.
- Added practical policy builders for API abuse protection, login protection,
  password reset throttling, third-party API clients, worker backpressure, and
  multi-tenant quotas.
- Added opt-in control diagnostics that analyze caller-provided control signals
  and return advice-only policy hints without changing settings automatically.
- Added observability export helpers for JSON lines, Prometheus-style text, and
  control-report metric conversion.
- Added batched observability export helpers and a service-guard pipeline recipe
  combining policy, deadline, fallback, and metric export.
- Added lock lease refresh and inspection APIs with stale-token protections and
  a compile-checked long-running lease recipe.
- Added deadline composition helpers for sharing one time budget across nested
  operations.
- Added getting started and adoption checklist documentation.
- Added practical recipes for API abuse protection, password reset throttling,
  and multi-tenant quotas.
- Added an experimental C ABI layer with duration, backoff, token bucket, fixed
  window, sliding window, circuit breaker, bulkhead, timeout, and deadline
  handles for future cross-language bindings.
- Added C ABI version reporting, diagnostic error text, budget ledger handles,
  and a C smoke example.
- Added language-neutral specification notes for portable FlowBrigade ports.
