# flowbrigade_prologue

Prologue middleware bridge for FlowBrigade.

This package keeps Prologue-specific code outside the core `flowbrigade`
package. Use it when a Prologue application wants FlowBrigade policies,
rate-limit headers, and HTTP denial responses as middleware.

For a practical adoption path, see
[docs/integrations-prologue.md](../../docs/integrations-prologue.md).

## Compatibility

| Package | Supported / tested version |
| --- | --- |
| Prologue | `>= 0.6.8`, tested with `0.6.8` Docker E2E and `0.6.10` source checkout |
| Nim | `>= 2.2.0` |
| FlowBrigade | `>= 0.1.0` |

Prologue is still evolving. Treat versions outside this range as unverified
until this bridge has been tested against them.

```nim
import prologue
import flowbrigade
import flowbrigade_prologue

proc hello(ctx: Context) {.async.} =
  resp "ok"

let policy = apiAbuseProtectionPolicy(
  perIdentityLimit = 120,
  perIdentityWindow = 1.min,
  globalRate = 1000,
  globalPer = 1.sec,
  globalBurst = 2000
)

var app = newApp()
app.use(rateLimitMiddleware(policy, forwardedForKey()))
app.get("/api", hello)
app.run()
```

Denied requests receive a `429` response by default. Allowed and denied
decisions include FlowBrigade's rate-limit headers.

## Key helpers

- `pathKey()`: limit by request path.
- `methodPathKey()`: limit by HTTP method and path.
- `headerKey("X-Account-ID")`: limit by an application-owned identity header.
- `forwardedForKey()`: limit by `X-Forwarded-For` or `X-Real-IP`.
- `queryParamKey("tenant")`: limit by query parameter.
- `postParamKey("account")`: limit by form-urlencoded POST parameter.
- `formParamKey("account")`: limit by parsed form parameter.
- `pathParamKey("tenant_id")`: limit by route path parameter.
- `cookieKey("session_id")`: limit by request cookie.
- `compoundKey("prefix", [partA, partB])`: combine multiple extracted values
  into one validated FlowBrigade key.

Only use `forwardedForKey` behind a trusted reverse proxy that overwrites or
sanitizes those headers. Otherwise callers can spoof their identity.

## Named limiter registry

Use a registry when an application wants to assemble limiters itself:

```nim
var registry = initLimiterRegistry()
registry.addLimiter("api", keyedFixedWindowDefinition(limit = 100, per = 1.min))

app.use(rateLimitMiddleware(registry, "api", headerKey("X-Account-ID")))
```

## Method-scoped limits

Use `allowedMethods` when only selected HTTP methods should consume capacity.

```nim
app.use(rateLimitMiddleware(
  policy,
  pathKey(),
  allowedMethods = {HttpPost}
))
```

Requests with other methods pass through without consuming the limiter.

## Config file helper

Use `prologueRateLimitMiddlewareFromFile` when a Prologue app should assemble
middleware from an INI-style config file:

```ini
[rate_limit]
policy = api_abuse
backend = thread_safe_memory
key = header
key_name = X-Account-ID
allowed_methods = POST
per_identity_limit = 120
per_identity_window = 1m
global_rate = 1000
global_per = 1s
global_burst = 2000
```

```nim
app.use(prologueRateLimitMiddlewareFromFile("flowbrigade.ini"))
```

Supported config backends are `memory` and `thread_safe_memory`.

## Login and password reset guards

Authentication-style guards combine an account key and a caller identity key.
This avoids treating every caller to the same account as one flat key, while
still keeping the key format consistent.

```nim
let loginPolicy = loginProtectionPolicy()

app.use(loginGuardMiddleware(
  loginPolicy,
  accountKey = headerKey("X-Account-ID"),
  identityKey = forwardedForKey()
))
```

Use `passwordResetGuardMiddleware` with `passwordResetProtectionPolicy` for
reset email or reset-token requests.

## Deadlines

Use `deadlineMiddleware` when the request pipeline already owns a deadline and
the Prologue layer should stop work after it expires.

```nim
let requestDeadline = initDeadline(after = 2.sec)
app.use(deadlineMiddleware(requestDeadline))
```

Expired requests receive `504` by default and the bridge emits
`X-FlowBrigade-Deadline-Remaining-Ms`.

## Threads and shared state

Prologue middleware closures must be `gcsafe`. The bridge exposes FlowBrigade
state through that Prologue boundary.

For single-process development and tests, in-memory policies are convenient.
For multi-process production deployments, prefer shared storage such as
Redis-backed FlowBrigade adapters. For multi-thread in-process deployments,
wrap shared in-memory policies or registries with `initThreadSafeFlowPolicy`
or `initThreadSafeLimiterRegistry`.

## Tests

Run the bridge tests after installing Prologue dependencies:

```sh
nimble test
```

See [TESTING.md](TESTING.md) for the Prologue bridge test report and covered
behavior matrix.

See `examples/login_deadline.nim` for a combined login guard and deadline
setup.
