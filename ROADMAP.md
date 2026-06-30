# Roadmap

This roadmap is intentionally conservative. FlowBrigade should stay focused on
flow-control building blocks for API clients, workers, batch jobs, CLIs,
workflow runtimes, and web services.

## Current: v0.1.1

The core package already includes:

- duration parsing, formatting, and unit helpers
- fixed, linear, and exponential backoff
- jitter modes
- sync and async retry
- fallback and async fallback
- retry, fallback, circuit-breaker, storage, budget, and control observer
  event shapes
- token bucket, fixed window, sliding window, keyed fixed window, and compound
  rate limiters
- rate-limit result metadata, non-consuming inspection, wait helpers,
  reservations, HTTP headers, HTTP decisions, and typed denial exceptions
- local limiter reset, configuration inspection, and state inspection helpers
- key builders and key extractors
- storage-backed fixed-window rate limiting
- sync and async rate-limit storage adapter surfaces
- in-memory rate-limit storage for tests and single-process tools
- Redis adapter package with fixed-window and token-bucket support
- `ready` Redis client bridge package
- experimental Memcached fixed-window adapter package
- budget/quota ledger
- throttle and debounce
- circuit breaker
- timeout and deadline composition helpers
- in-process bulkhead and keyed bulkhead
- framework-neutral lock store contract with lease refresh and inspection
- limiter registry and named/compound limiter definitions
- config objects and presets
- practical policy builders for login, password reset, API abuse, API clients,
  worker backpressure, and multi-tenant quotas
- policy validation reports for startup checks and config dry-runs
- opt-in control diagnostics and advice-only policy hints
- metric event conversion and observability export helpers
- Prologue bridge package with middleware, request key helpers, config helpers,
  and version notes
- thread-safe wrappers for shared in-process policies and registries
- compile-checked recipes and adoption documentation
- experimental C ABI with ARC default build, keyed fixed-window handles, keyed
  bulkhead handles, local limiter management helpers, callback retry/fallback,
  limiter registry operations, callback-backed stored fixed windows, metrics
  export helpers, and feature checks

## Unreleased / v0.2 Candidate

- Redis-backed keyed token bucket adapter support

## Next Candidates

These are reasonable next areas if they stay small and well-tested:

- C ABI smoke coverage for more direct handle combinations
- optional leak-check workflow using Valgrind or sanitizers when available
- richer policy/config examples for non-web workers and batch runtimes
- more benchmarks around hot limiter paths and storage adapter overhead
- deeper adapter documentation for Redis, Memcached, and third-party client
  responsibility boundaries
- additional Prologue adoption examples without making core web-specific
- language binding experiments built on the C ABI, starting with Rust/Zig
  wrappers if the ABI remains stable enough

## Not Planned For Core

- timezone handling
- calendar math
- date formatting
- localization
- relative humanized date text
- cron scheduling
- built-in authentication or authorization
- complete DDoS protection
- built-in cryptographic hashing or encryption
- built-in Redis, Memcached, or database dependency in the core package
- framework-specific middleware inside the core package
- generic cache or storage abstraction unrelated to flow control

Some of these may make sense as separate packages or integrations later.
