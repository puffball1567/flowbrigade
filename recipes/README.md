# Recipes

Recipes are complete, compile-checked examples for common FlowBrigade use cases.

- `api_client_retry.nim`: retry an API call with exponential backoff and observer events.
- `login_rate_limit.nim`: build validated keys and return rate-limit headers.
- `worker_backpressure.nim`: combine token bucket, circuit breaker, and timeout.
- `failure_modes.nim`: choose fail-closed or fail-open behavior for storage failures.
- `observability_hooks.nim`: collect retry, circuit breaker, and stored limiter events.
- `named_limiters.nim`: combine named limiters, extracted keys, and HTTP decisions.
- `http_api_abuse_protection.nim`: rate-limit anonymous and authenticated API callers.
- `password_reset_throttle.nim`: throttle reset email attempts with fail-closed storage.
- `multi_tenant_quota.nim`: combine tenant and per-user quotas with plan-specific limits.
- `policy_builder.nim`: start from complete operational policy bundles.
- `control_diagnostics.nim`: produce advice-only control hints from recent signals.
- `observability_export.nim`: export FlowBrigade events as JSON lines or text metrics.
- `fallback_api_client.nim`: try secondary providers after a primary provider fails.
- `async_fallback_api_client.nim`: async fallback across ordered providers.
- `lease_refresh.nim`: extend a lock lease during long-running critical work.
- `deadline_composition.nim`: pass one time budget through nested operations.
- `service_guard_pipeline.nim`: combine policy, deadline, fallback, and metric export.
- `redis_distributed_limit.nim`: shape for Redis-backed distributed limits using `ready`.

Dependency-free recipes are checked in CI by default. The Redis recipe is
checked when the `ready` bridge dependency is available.
