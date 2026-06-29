import std/nativesockets

import prologue
import flowbrigade
import flowbrigade_prologue

proc health(ctx: Context) {.async.} =
  resp "ok"

proc limited(ctx: Context) {.async.} =
  resp "limited ok"

proc expired(ctx: Context) {.async.} =
  resp "deadline ok"

proc login(ctx: Context) {.async.} =
  resp "login ok"

let limitedPolicy = apiAbuseProtectionPolicy(
  perIdentityLimit = 1,
  perIdentityWindow = 1.min,
  globalRate = 100,
  globalPer = 1.sec,
  globalBurst = 100
)

let loginPolicy = loginProtectionPolicy(
  accountLimit = 1,
  accountWindow = 1.min,
  identityLimit = 10,
  identityWindow = 1.hr
)

let expiredDeadline = initDeadline(after = 0.sec)

let settings = newSettings(
  address = "0.0.0.0",
  port = Port(8080),
  debug = false,
  secretKey = "flowbrigade-e2e"
)

var app = newApp(settings = settings)
app.get("/health", health)
app.get("/limited", limited, middlewares = @[
  rateLimitMiddleware(limitedPolicy, pathKey())
])
app.get("/deadline", expired, middlewares = @[
  deadlineMiddleware(expiredDeadline)
])
app.post("/login", login, middlewares = @[
  loginGuardMiddleware(
    loginPolicy,
    accountKey = headerKey("X-Account-ID"),
    identityKey = forwardedForKey()
  )
])

app.run()
