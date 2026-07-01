# Performance notes

FlowBrigade should stay predictable under routine application load. These notes
document the expected cost model and the local smoke benchmarks available for
regression checks. They are not official cross-machine performance claims.

## Core limiters

In-memory limiters are O(1) for normal `inspect`, `consume`, and `allow` calls.
Keyed limiters and in-memory storage use hash tables.

Key-capacity guards may prune expired entries when a new key would exceed the
configured capacity. That pruning scans stored keys, so configure `maxKeys`
according to the memory budget and expected key churn.

## Duration parsing

Duration parsing is linear in input length and rejects oversized input through a
configurable maximum length. Keep the default maximum unless the application has
a concrete reason to accept larger values.

## Redis adapter

Redis fixed-window, token-bucket, and keyed token-bucket operations are one
`EVAL` call each. This keeps decisions atomic but means network latency
dominates per-request cost.

Use Redis-backed limiters when state must be shared across processes. For
single-process tools, in-memory limiters avoid network cost.

For localhost or Docker Redis checks, run the optional real-server benchmark:

```sh
FLOWBRIGADE_REDIS_HOST=127.0.0.1 FLOWBRIGADE_REDIS_PORT=6379 nimble benchmarkRedis
```

Set `FLOWBRIGADE_REDIS_BENCH_ITERATIONS` to adjust the iteration count. This
benchmark uses a persistent TCP socket and Redis RESP directly so it measures
Redis round trips rather than `redis-cli` process startup time.

## Benchmark smoke tests

A small benchmark smoke suite lives in `benchmarks/core_bench.nim` and
`benchmarks/redis_adapter_bench.nim`. It can be run with:

```sh
nimble benchmark
```

These numbers are intended for local comparison while changing code. They are
not a substitute for application-level measurements.

## Further benchmark candidates

Before publishing a larger release, add repeatable benchmarks for:

- duration parser throughput on invalid inputs
- in-memory token bucket, GCRA, keyed GCRA, fixed window, and sliding window
  `consume`
- keyed limiter behavior near `maxKeys`
- stored fixed-window in-memory adapter throughput
- Redis fixed-window `consume` latency against a real server

Benchmarks should run separately from unit tests so CI remains fast.
