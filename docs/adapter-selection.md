# Adapter selection model

FlowBrigade should support external storage through explicit, documented
provider choices.

The user-facing model is:

1. choose the storage family
2. choose the supported OSS client or bridge
3. receive FlowBrigade's abstract storage surface

Example shape:

```nim
let storage = initFlowBrigadeStorage(
  backend = redis,
  provider = ready,
  connection = client
)
```

The exact helper name may differ per bridge package, but the responsibility
boundary should stay consistent.

## Layers

### Core

`flowbrigade` owns:

- `RateLimitStorage`
- `AsyncRateLimitStorage`
- limiter behavior
- result metadata
- validation rules
- tests for the abstract contract

The core package does not own network clients.

### Storage-family adapters

Storage-family packages define what operations a backend must provide.

Current packages:

- `flowbrigade_redis`
- `flowbrigade_memcached`

These packages own:

- backend-specific callback contracts
- backend-specific safety notes
- fake-backend unit tests
- conversion to `RateLimitStorage` or `AsyncRateLimitStorage`

They do not need to depend on every concrete client.

### Client bridge packages

Client-specific bridge packages should connect a known OSS client to the
storage-family adapter.

Suggested naming:

- `flowbrigade_redis_<client>`
- `flowbrigade_memcached_<client>`

Bridge packages own:

- concrete client calls
- response parsing
- connection-specific error mapping
- real-service integration tests
- compatibility notes for the client version they support

## Supported Matrix

Only documented combinations should be treated as officially supported.

| Storage | Package | Provider | Status |
| --- | --- | --- | --- |
| Redis | `flowbrigade_redis` | raw `EVAL` callback | supported |
| Redis | `flowbrigade_redis` | raw command callback | supported |
| Redis | `flowbrigade_ready` | `ready` | supported |
| Memcached | `flowbrigade_memcached` | `gets`/`add`/`cas`/`delete` callback | experimental |

Client-specific bridges should be added to this matrix only after they have
integration tests against the real service.

## Framework Bridges

| Framework | Package | Surface | Status |
| --- | --- | --- | --- |
| Prologue `>= 0.6.8` | `flowbrigade_prologue` | rate-limit middleware, auth guards, deadline middleware | experimental; tested with Prologue `0.6.8` Docker E2E and `0.6.10` source checkout; includes method-scoped limits, request key helpers, and config helpers |

Framework bridge packages should be versioned separately from the core package
and should not add framework dependencies to `flowbrigade` itself.

## Evaluated Providers

| Provider | Decision | Reason |
| --- | --- | --- |
| `ready` | supported | Exposes raw Redis commands, compiles on Nim 2.2, and passes real Redis integration tests. |
| `redis` | not bridged yet | Official client, but no public raw `EVAL`/command surface was found for the current adapter shape. |
| `redisclient` | not supported on Nim 2.2 | API shape is suitable, but `redisparser 0.1.1` fails to compile on Nim 2.2 during evaluation. |
| `asyncredis` | not bridged yet | Scripting is documented as not stable/tested in the evaluated package. |

These decisions can change if upstream APIs or compatibility improve.

## Bridge Requirements

A bridge package must:

- expose a small initializer that returns FlowBrigade storage
- document the exact OSS client and version range it supports
- map client errors deliberately instead of swallowing them silently
- prove `inspect` does not consume capacity
- prove `consume` is atomic enough for its backend
- prove `clear` removes exactly one limiter key
- test TTL/window rollover against the real service
- document fail-open/fail-closed recommendations

## User Choice

Users should be able to choose:

- the in-memory DB or external storage family
- the concrete OSS client they already use
- whether they want sync or async storage
- whether storage failure should fail open or fail closed

FlowBrigade's job is to make these choices explicit and testable, not to hide
the operational differences between Redis, Memcached, and future backends.
