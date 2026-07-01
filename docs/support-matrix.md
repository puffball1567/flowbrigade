# Support matrix

This document defines what is currently supported and what is experimental.

## Core

| Area | Status |
| --- | --- |
| Duration parsing/formatting | Supported |
| Backoff and jitter | Supported |
| Sync retry | Supported |
| Async retry | Supported |
| Retry allowance | Supported |
| Fallback / try-in-order | Supported |
| Async fallback / async try-in-order | Supported |
| Token bucket | Supported |
| GCRA limiter | Supported |
| Keyed GCRA limiter | Supported |
| Fixed window | Supported |
| Sliding window | Supported |
| Keyed fixed window | Supported |
| Compound limiter | Supported |
| Budget / quota ledger | Supported |
| HTTP rate-limit headers | Supported |
| Wait helpers | Supported |
| Key builders | Supported |
| Key extractors | Supported |
| Rate string parser | Supported |
| Limiter registry | Supported |
| Framework-neutral HTTP decisions | Supported |
| Adapter capabilities | Supported |
| Rate-limit reservations | Supported |
| Throttle | Supported |
| Debounce | Supported |
| Circuit breaker | Supported |
| Timeout | Supported |
| Deadline composition | Supported |
| Bulkhead | Supported |
| Keyed bulkhead | Supported |
| Lock store contract | Supported |
| Lock lease refresh and inspection | Supported |
| Config objects | Supported |
| Policy presets | Supported |
| Practical policy builders | Supported |
| Policy validation reports | Supported |
| Control diagnostics / policy hints | Supported |
| Metric event conversion | Supported |
| Observability export helpers | Supported |
| C ABI layer | Experimental |
| Internal time source | Internal test support |

## Storage Surfaces

| Surface | Status | Notes |
| --- | --- | --- |
| `RateLimitStorage` | Supported | Sync storage adapter surface. |
| `AsyncRateLimitStorage` | Supported | Async storage adapter surface. |
| `InMemoryRateLimitStorage` | Supported | Tests and single-process use. |
| `StoredFixedWindow` | Supported | Fixed-window storage-backed limiter. |
| `AsyncStoredFixedWindow` | Supported | Async fixed-window storage-backed limiter. |

## Adapter Packages

| Package | Status | Notes |
| --- | --- | --- |
| `flowbrigade_redis` | Supported | Redis fixed-window, token-bucket, and keyed token-bucket adapter. |
| `flowbrigade_ready` | Supported | Bridge for the `ready` Redis client. |
| `flowbrigade_memcached` | Experimental | Fixed-window adapter contract. Fake and optional real-server tests. |

## Framework Bridge Packages

| Package | Status | Notes |
| --- | --- | --- |
| `flowbrigade_prologue` | Experimental | Prologue `>= 0.6.8`, tested with `0.6.8` Docker E2E and `0.6.10` source checkout; rate-limit middleware, auth guards, deadline middleware, key helpers, HTTP headers, and config helpers. |

## Backend Requirements

Redis-backed consume operations must be atomic. The official Redis adapter uses
Lua scripts for this.

Memcached-backed consume operations require real `gets`/`cas` semantics from
the chosen client. Without that, the adapter should not be treated as safe for
distributed rate limiting.

## Unsupported

FlowBrigade does not currently support:

- public calendar/date/timezone APIs
- framework-specific middleware as part of core
- generic cache or storage abstraction unrelated to rate limiting
- complete DDoS protection
- built-in cryptographic hashing or encryption
- built-in authentication or authorization
- Jester integration as a packaged framework bridge
