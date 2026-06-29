# Prologue bridge test report

This report summarizes the FlowBrigade Prologue bridge checks that are covered
by `tests/test_flowbrigade_prologue.nim`.

## Environment

| Item | Value |
| --- | --- |
| Nim | `2.2.10` |
| Prologue | `0.6.8` Docker E2E and `0.6.10` source checkout |
| FlowBrigade bridge | `packages/flowbrigade_prologue` |
| Test style | Prologue `mockApp` / `runOnce` middleware tests |

## Latest local result

The following command passed locally:

```sh
nim r --nimcache:/tmp/flowbrigade-prologue-nimcache \
  -p:packages/flowbrigade_prologue/src \
  -p:src \
  packages/flowbrigade_prologue/tests/test_flowbrigade_prologue.nim
```

In this workspace the unit command also used local Prologue dependency paths
under `/tmp/flowbrigade-prologue-src` and `/tmp/flowbrigade-prologue-nimble`.
The Docker E2E command installed Prologue through Nimble and compiled against
`prologue-0.6.8`.

## Covered behavior

| Area | Result |
| --- | --- |
| Allowed rate-limited request | Passes through to the Prologue handler and returns `200`. |
| Denied rate-limited request | Stops middleware execution and returns `429`. |
| Rate-limit headers | Adds FlowBrigade rate-limit headers on middleware decisions. |
| Custom denied body | Returns caller-provided denied body. |
| Disabled rate-limit headers | Omits rate-limit headers when `noRateLimitHeaders` is selected. |
| Custom denied content type | Sets caller-provided `Content-Type` for denied responses. |
| Header key extraction | Isolates callers by request header value. |
| Query parameter key extraction | Isolates callers by query parameter value. |
| Path parameter key extraction | Reads route path parameters through Prologue request data. |
| Cookie key extraction | Reads request cookies through Prologue request data. |
| Compound key extraction | Combines multiple extracted values through FlowBrigade key validation. |
| Named limiter registry middleware | Consumes a named limiter from `LimiterRegistry`. |
| Method-scoped middleware | Consumes capacity only for configured HTTP methods. |
| Thread-safe policy overload | Accepts `ThreadSafeFlowPolicy` in middleware. |
| Config file API abuse middleware | Builds method-scoped thread-safe API middleware from INI config. |
| Config file login middleware | Builds login guard middleware from a named INI section. |
| Login guard middleware | Combines account and identity keys. |
| Password reset guard middleware | Uses password-reset defaults and denial body. |
| Deadline middleware | Allows before expiry and returns `504` after expiry. |
| Invalid configuration | Rejects blank names, nil key procs, empty compound keys, and blank limiter names. |

## Notes

- These tests use Prologue's mocked request pipeline, so they verify middleware
  behavior without opening a network socket.
- Docker E2E coverage lives in `e2e/` and verifies the bridge through a running
  Prologue app.
- Multi-process rate limiting still requires shared storage such as Redis.
  `ThreadSafeFlowPolicy` only protects shared in-process state.
