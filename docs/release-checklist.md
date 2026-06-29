# Release checklist

## Package order

1. Publish `flowbrigade`.
2. Publish `flowbrigade_redis`.
3. Publish `flowbrigade_ready`.
4. Publish `flowbrigade_memcached` as experimental after the real Memcached
   integration test has passed.

Adapter packages declare dependencies on `flowbrigade` or another adapter
package, so their Nimble dependency resolution is easiest after the lower-level
package has been published.

Use this before publishing a tagged release.

## Local verification

```sh
nim r --nimcache:/tmp/flowbrigade-nimcache -p:src tests/all.nim
nim check --nimcache:/tmp/flowbrigade-nimcache -p:src src/flowbrigade.nim
nim doc --nimcache:/tmp/flowbrigade-nimcache -p:src --outdir:/tmp/flowbrigade-docs src/flowbrigade.nim
nimble --nimbleDir:/tmp/flowbrigade-nimble --useSystemNim check
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim benchmark
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim snippets
nim r --nimcache:/tmp/flowbrigade-redis-nimcache -p:packages/flowbrigade_redis/src -p:src packages/flowbrigade_redis/tests/test_flowbrigade_redis.nim
nim r --nimcache:/tmp/flowbrigade-memcached-nimcache -p:packages/flowbrigade_memcached/src -p:src packages/flowbrigade_memcached/tests/test_flowbrigade_memcached.nim
nim r --nimcache:/tmp/flowbrigade-memcached-nimcache -p:packages/flowbrigade_memcached/src -p:src packages/flowbrigade_memcached/tests/test_flowbrigade_memcached_integration.nim
```

When `ready` is installed locally, run:

```sh
nim r --nimcache:/tmp/flowbrigade-ready-nimcache -p:packages/flowbrigade_ready/src -p:packages/flowbrigade_redis/src -p:src packages/flowbrigade_ready/tests/test_flowbrigade_ready.nim
```

When Redis is available locally, run:

```sh
nim r --nimcache:/tmp/flowbrigade-redis-nimcache -p:packages/flowbrigade_redis/src -p:src packages/flowbrigade_redis/tests/test_flowbrigade_redis_integration.nim
nim r --nimcache:/tmp/flowbrigade-ready-nimcache -p:packages/flowbrigade_ready/src -p:packages/flowbrigade_redis/src -p:src packages/flowbrigade_ready/tests/test_flowbrigade_ready_integration.nim
```

The Memcached integration test prints `SKIP:` with a reason when Memcached is
not installed or not running.

See [local-services.md](local-services.md) for manual start/stop commands and
environment variables used by integration tests.

If Nimble cannot discover the active Nim binary:

```sh
nimble --nimbleDir:/tmp/flowbrigade-nimble --offline --nim:/path/to/nim test
```

## API review

- Public imports work through `import pkg/flowbrigade`.
- Focused imports work for category modules such as `pkg/flowbrigade/durations`.
- `flowbrigade/internal/time_source` remains documented as internal test support.
- Carbon-style date/time convenience APIs are not included.
- New behavior is listed in `docs/test-matrix.md`.
- Supported and experimental areas are listed in `docs/support-matrix.md`.
- Compatibility expectations are listed in `docs/api-stability.md`.

## Documentation

- README examples compile mentally against the public API.
- Getting started and adoption checklist reflect the current public API.
- README snippets and dependency-free recipes pass `nimble snippets`.
- Failure-mode and observability recipes pass `nimble snippets`.
- `CONTRIBUTING.md` mentions new test files.
- `ROADMAP.md` reflects what is shipped and what remains future work.
- `LICENSE` year and package metadata are correct.
- `SECURITY.md` reflects current operational limits.
- `CHANGELOG.md` records notable changes.
- Adapter README files explain supported providers and responsibility boundaries.
- Local service notes stay limited to FlowBrigade verification needs; service
  hardening and configuration remain upstream documentation concerns.

## Publishing

- Confirm the Nimble package name is still available.
- Confirm the GitHub repository name is final.
- Confirm `.git` is a real repository and CI can run on GitHub.
- Tag the release after CI passes.
