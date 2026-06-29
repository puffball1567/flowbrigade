# API stability

FlowBrigade is pre-1.0, but public APIs should still change deliberately.

## Stable Enough For Early Use

These APIs are intended to be kept source-compatible where practical:

- duration parsing and formatting
- duration unit helpers
- backoff policies and jitter modes
- sync and async retry
- token bucket, fixed window, sliding window, and keyed fixed window limiters
- `RateLimitResult`
- `inspect`, `consume`, and `allow` limiter semantics
- `RateLimitStorage`
- `AsyncRateLimitStorage`
- rate-limit header helpers
- key builders
- fail-open/fail-closed wrapper
- throttle, debounce, circuit breaker, and timeout helpers

Breaking changes in these areas should be justified in the changelog and should
come with migration notes.

## Experimental Or Adapter-Specific

These are usable, but may still evolve as real integrations are added:

- `flowbrigade_memcached`
- client-specific bridge packages such as `flowbrigade_ready`
- adapter package layout and naming
- benchmark output format

## Internal

`flowbrigade/internal/time_source` exists to keep tests deterministic and to
support elapsed-time control logic. It is not a public clock/date API.

## Change Rules

Before changing public behavior:

1. Add or update tests first.
2. Update `docs/test-matrix.md`.
3. Update README examples when user-facing behavior changes.
4. Update adapter docs when a backend contract changes.
5. Add migration notes when existing code must change.

## Versioning Before 1.0

Minor versions may add features or adjust experimental APIs. Patch versions
should be reserved for fixes, documentation corrections, and compatibility
improvements.
