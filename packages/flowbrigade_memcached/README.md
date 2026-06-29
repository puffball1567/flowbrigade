# flowbrigade_memcached

Memcached storage adapter helpers for FlowBrigade rate limiting.

This package intentionally does not depend on a specific Memcached client.
Provide callbacks that map to your client's `gets`, `add`, `cas`, and `delete`
operations.

Client-specific bridge packages can build on this package. A bridge should
choose one supported OSS client, call that client correctly, and return
FlowBrigade's abstract `RateLimitStorage`.

```nim
import std/times
import pkg/flowbrigade/ratelimit
import pkg/flowbrigade_memcached

let memcachedStorage = initMemcachedRateLimitStorage(
  gets = proc(key: string): MemcachedGetResult =
    # Call your client's gets command and return value plus CAS token.
    discard,
  add = proc(key, value: string; ttl: Duration): bool =
    # Add only when the key does not exist, with TTL.
    discard,
  cas = proc(key, value, cas: string; ttl: Duration): bool =
    # Compare-and-swap using the CAS token returned by gets.
    discard,
  delete = proc(key: string): bool =
    # Delete one key.
    discard
)

let limiter = initStoredFixedWindow(
  prefix = "api",
  limit = 100,
  per = initDuration(minutes = 1),
  storage = memcachedStorage.asRateLimitStorage()
)

discard limiter.consume("user:42")
```

## Why CAS?

Memcached does not provide Redis-style Lua scripting. This adapter uses
`gets`/`cas` so consuming capacity can avoid overwriting concurrent updates.
When a CAS conflict occurs, the adapter retries up to `maxCasRetries`.

The first implementation supports fixed-window rate limiting. Token bucket
support is intentionally not included yet because it needs stronger guarantees
around time and concurrent refill updates than Memcached usually provides.

## Tests

Run the fake Memcached unit tests:

```sh
nimble test
```

Run the real Memcached integration test when a server is available:

```sh
nimble integration
```

The integration test uses `FLOWBRIGADE_MEMCACHED_HOST` and
`FLOWBRIGADE_MEMCACHED_PORT`, defaulting to `127.0.0.1:11211`.
If Memcached is unavailable, the test prints a `SKIP:` line with the reason.
