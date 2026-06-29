# FlowBrigade examples

These examples are intentionally small and dependency-free so they can be checked in CI.

- `duration_config.nim` parses human-readable duration strings used in config or CLI input.
- `retry_api_client.nim` retries a fallible operation with backoff and injectable sleep.
- `rate_limit_headers.nim` turns a rate-limit decision into HTTP-compatible headers.
- `worker_control.nim` combines throttle, timeout, and circuit breaker style flow control.

Redis examples live in `packages/flowbrigade_redis` because they need a running Redis server or a Redis client adapter.
