import prologue
import flowbrigade
import flowbrigade_prologue

proc login(ctx: Context) {.async.} =
  resp "ok"

let loginPolicy = loginProtectionPolicy(
  accountLimit = 5,
  accountWindow = 15.min,
  identityLimit = 20,
  identityWindow = 1.hr
)

let requestDeadline = initDeadline(after = 2.sec)

var app = newApp()
app.use(deadlineMiddleware(requestDeadline))
app.use(loginGuardMiddleware(
  loginPolicy,
  accountKey = headerKey("X-Account-ID"),
  identityKey = forwardedForKey()
))
app.post("/login", login)

when isMainModule:
  app.run()
