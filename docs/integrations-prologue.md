# Prologue integration

FlowBrigade is framework-neutral. The `flowbrigade_prologue` package is a thin
adapter that turns FlowBrigade decisions into Prologue middleware.

Use it when a Prologue application needs rate limiting, login attempt guards,
password reset throttling, or request deadlines without putting Prologue-specific
logic into the core `flowbrigade` package.

## Install

After publication, install the core package and the Prologue bridge:

```sh
nimble install flowbrigade
nimble install flowbrigade_prologue
```

For local development from this repository, compile with both source paths:

```sh
nim r -p:src -p:packages/flowbrigade_prologue/src your_app.nim
```

## Basic API limit

```nim
import prologue
import flowbrigade
import flowbrigade_prologue

proc api(ctx: Context) {.async.} =
  resp "ok"

let policy = apiAbuseProtectionPolicy(
  perIdentityLimit = 120,
  perIdentityWindow = 1.min,
  globalRate = 1000,
  globalPer = 1.sec,
  globalBurst = 2000
)

var app = newApp()
app.use(rateLimitMiddleware(policy, headerKey("X-Account-ID")))
app.get("/api", api)
app.run()
```

## Configure from a file

For Prologue apps that should switch behavior without editing Nim code, load an
INI-style config file:

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

Then attach the configured middleware:

```nim
app.use(prologueRateLimitMiddlewareFromFile("flowbrigade.ini"))
```

Supported `backend` values are `memory` and `thread_safe_memory`. Distributed
state still needs an explicit storage-backed FlowBrigade adapter in application
code.

Login guards can use another section:

```ini
[login_guard]
policy = login
backend = memory
account_key = header
account_key_name = X-Account-ID
identity_key = forwarded_for
account_limit = 5
account_window = 15m
identity_limit = 20
identity_window = 1h
```

```nim
app.use(prologueRateLimitMiddlewareFromFile("flowbrigade.ini", "login_guard"))
```

## Login guard

Use account and identity keys together. This prevents all callers to one account
from being flattened into one bucket, while still limiting repeated attempts.

```nim
let loginPolicy = loginProtectionPolicy()

app.use(loginGuardMiddleware(
  loginPolicy,
  accountKey = headerKey("X-Account-ID"),
  identityKey = forwardedForKey()
))
```

Only use `forwardedForKey` when a trusted reverse proxy overwrites or sanitizes
`X-Forwarded-For` and `X-Real-IP`.

## Method-scoped limits

Limit only selected HTTP methods when read requests should not consume capacity.

```nim
app.use(rateLimitMiddleware(
  apiAbuseProtectionPolicy(),
  pathKey(),
  allowedMethods = {HttpPost}
))
```

## Key choices

Choose keys from stable application-owned identity. Available helpers include:

| Helper | Use |
| --- | --- |
| `headerKey("X-Account-ID")` | Trusted application identity header. |
| `queryParamKey("tenant")` | Tenant or public API key in query params. |
| `pathParamKey("tenant_id")` | Route parameter. |
| `cookieKey("session_id")` | Session-oriented limits. |
| `methodPathKey()` | Per-method route limits. |
| `compoundKey("login", [accountKey, identityKey])` | Multi-part validated keys. |

Prefer opaque or non-sensitive identifiers. Do not build limiter keys directly
from secrets.

## Shared state

In-memory policies are useful for one process. For multi-thread in-process
servers, wrap shared policies:

```nim
let policy = initThreadSafeFlowPolicy(apiAbuseProtectionPolicy())
app.use(rateLimitMiddleware(policy, headerKey("X-Account-ID")))
```

For multi-process deployments, use shared storage such as Redis-backed
FlowBrigade adapters.

## Verification

The Prologue bridge test report is in
[packages/flowbrigade_prologue/TESTING.md](../packages/flowbrigade_prologue/TESTING.md).
