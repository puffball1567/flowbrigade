# Contributing

Thanks for helping improve `flowbrigade`.

This project is intentionally small. Contributions should keep the package
focused on time-based control utilities.

The English version of this file is the source of truth. Short multilingual
guides are also available:

- Japanese: [docs/contributing-ja.md](docs/contributing-ja.md)
- French: [docs/contributing-fr.md](docs/contributing-fr.md)
- German: [docs/contributing-de.md](docs/contributing-de.md)

## Scope

Good fits:

- duration parsing and formatting
- retry and backoff behavior
- jitter behavior
- rate limiting
- keyed in-memory limiters
- deterministic tests for time-dependent behavior
- documentation and examples
- storage adapter contracts and client bridge packages that preserve
  FlowBrigade's rate-limit semantics

Out of scope:

- public `Clock` APIs
- timezone handling
- calendar math
- date formatting
- localization
- relative display text such as "3 minutes ago"
- HTTP-framework-specific middleware
- distributed or persistent rate limiting in core
- generic storage/cache abstraction unrelated to rate limiting

## Development Setup

Run all tests from the repository root:

```sh
nim r --nimcache:/tmp/flowbrigade-nimcache -p:src tests/all.nim
```

Check the package entry point:

```sh
nim check --nimcache:/tmp/flowbrigade-nimcache -p:src src/flowbrigade.nim
```

Build docs:

```sh
nim doc --nimcache:/tmp/flowbrigade-nimcache -p:src --outdir:/tmp/flowbrigade-docs src/flowbrigade.nim
```

Run adapter package tests when the change touches `packages/`:

```sh
nim r --nimcache:/tmp/flowbrigade-redis-nimcache -p:packages/flowbrigade_redis/src -p:src packages/flowbrigade_redis/tests/test_flowbrigade_redis.nim
nim r --nimcache:/tmp/flowbrigade-memcached-nimcache -p:packages/flowbrigade_memcached/src -p:src packages/flowbrigade_memcached/tests/test_flowbrigade_memcached.nim
```

If you use Nimble locally and your environment cannot write to `~/.nimble`, pass
a temporary Nimble directory:

```sh
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim test
```

The explicit `--nim` flag is only needed when Nimble cannot discover the active
Nim binary.

## TDD Workflow

Prefer tests first for new behavior.

1. Add or update a focused test in `tests/`.
2. Run the test and confirm it fails for the expected reason.
3. Implement the smallest clear change.
4. Run `tests/all.nim`.
5. Update README or design notes if the public behavior changed.

Missing tests are useful contributions. If you notice an edge case, failure
mode, or interaction that is not covered yet, please add a focused test even if
the implementation already appears to work.

Bug reports are welcome, but fixes are even more helpful when practical. If you
find a bug and can safely fix it, please include the fix and a regression test
in the same pull request.

## File Layout

Public category modules live under `src/flowbrigade/`:

- `durations.nim`
- `backoff.nim`
- `retry.nim`
- `ratelimit.nim`

Feature implementations live in subdirectories:

- `src/flowbrigade/durations/`
- `src/flowbrigade/backoff/`
- `src/flowbrigade/retry/`
- `src/flowbrigade/ratelimit/`

Avoid adding vague modules such as `utils.nim`. Prefer specific names that
describe the behavior being added.

## Tests

Keep tests close to the feature being changed:

- duration parser changes: `tests/test_durations_parse.nim`
- duration formatter changes: `tests/test_durations_format.nim`
- backoff changes: `tests/test_backoff_policies.nim`
- jitter changes: `tests/test_backoff_jitter.nim`
- retry changes: `tests/test_retry_sync.nim`
- async retry changes: `tests/test_retry_async.nim`
- fallback changes: `tests/test_fallback.nim` and `tests/test_fallback_async.nim`
- rate limiter changes: `tests/test_ratelimit_*.nim`
- budget/quota changes: `tests/test_budget.nim`
- policy builder changes: `tests/test_policy.nim`
- control diagnostics changes: `tests/test_control_diagnostics.nim`
- observability export changes: `tests/test_observability.nim`
- adapter changes: `packages/<adapter>/tests/`
- throttle changes: `tests/test_throttle.nim`
- debounce changes: `tests/test_debounce.nim`
- circuit breaker changes: `tests/test_circuit_breaker.nim`
- timeout changes: `tests/test_timeout.nim`

Time-dependent tests should use the internal manual time source instead of real
sleeping.

When adding or changing behavior, update [docs/test-matrix.md](docs/test-matrix.md)
if the coverage map changes.

Update [docs/support-matrix.md](docs/support-matrix.md) when a feature moves
between experimental and supported.

## Public API

Public names should be small and predictable. Prefer names that can be explained
in a README example without extra setup.

When adding new behavior, document:

- what the feature does
- what it does not do
- how errors are reported
- whether it depends on real time, randomness, or external state

## Security

For features that store per-key or per-client state, include bounded-memory
behavior or document why the state cannot grow with untrusted input.

For features that parse untrusted input, include length limits, overflow tests,
and error-path tests.

Update `SECURITY.md` when a change affects operational limits or security
assumptions.
