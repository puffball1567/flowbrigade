# Adapter policy

FlowBrigade keeps the core package dependency-free. External systems such as
Redis, Memcached, databases, and framework middleware should live in separate
packages.

For provider selection and bridge package rules, see
`docs/adapter-selection.md`.

## Framework bridges

Framework bridges live outside the core package for the same reason storage
adapters do: the core package should stay framework-neutral.

`packages/flowbrigade_prologue` is the first framework bridge. It exposes
Prologue middleware for FlowBrigade policies and named limiter registries.
The bridge translates FlowBrigade's framework-neutral HTTP decisions into
Prologue response fields and headers.

Framework bridges should:

- keep framework imports outside `src/flowbrigade`
- use FlowBrigade's framework-neutral result types where possible
- provide framework-native middleware examples
- document request identity assumptions such as trusted proxy headers
- include framework mocking or integration tests

## Redis

`packages/flowbrigade_redis` is the first official adapter package.

It supports:

- stored fixed-window rate limiting through `RateLimitStorage`
- Redis-backed token bucket rate limiting
- raw `EVAL` callback integration
- raw command callback integration for clients that expose `execCommand`

The adapter uses Lua scripts because Redis executes each script atomically.
Callers do not need to write Lua.

## Async adapters

The core package exposes both synchronous and asynchronous storage surfaces.
The synchronous `RateLimitStorage` keeps small tools, tests, and blocking Redis
clients simple. `AsyncRateLimitStorage` and `AsyncStoredFixedWindow` provide a
parallel surface for async clients.

Async adapters should:

- keep the same decision semantics as the sync adapter
- return `Future[RateLimitResult]`
- avoid changing existing synchronous callback types
- keep Lua scripts shared with the sync Redis adapter where possible
- include integration tests against a real Redis server

`asAsyncRateLimitStorage` wraps a synchronous storage adapter for compatibility.
It does not make blocking I/O non-blocking. True async clients should implement
`AsyncRateLimitStorage` directly.

## Other storage backends

Memcached or database adapters are useful candidates, but they must prove their
consume operation can be made atomic enough for the limiter they expose.

Adapters should document whether they are safe across processes and what
failure behavior callers should use with `failOpen` or `failClosed`.

Client-specific bridges should be separate packages. A bridge chooses a
supported OSS client, calls that client correctly, and returns FlowBrigade's
abstract storage type. Users can then choose both the storage family and the OSS
client while FlowBrigade keeps a clear support matrix.

## Memcached direction

Memcached lives in `packages/flowbrigade_memcached`.

The first supported target is fixed-window rate limiting. A token bucket is
harder because Memcached does not provide Redis-style server-side scripting.

The adapter uses:

- `add` for first-use initialization with TTL
- `gets` / `cas` for compare-and-swap updates
- `delete` for clear operations

The adapter does not use `incr` for consume because a denied over-increment
would need rollback or compensation. CAS keeps the decision and update tied to
the observed value.

Still-open areas:

- TTL edge cases around window reset
- real-client integration tests once a Memcached client is chosen
- whether a separate async Memcached adapter should be added

The adapter should only claim distributed safety for clients that provide real
`gets`/`cas` semantics.
