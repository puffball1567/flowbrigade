import flowbrigade

var limiter = initKeyedFixedWindow[string](
  limit = 5,
  per = 1.min,
  maxKeys = 10_000
)

let key = rateLimitKey(["login", "user-42"])
let decision = limiter.consume(key)

if not decision.allowed:
  let headers = rateLimitHeadersTable(decision)
  doAssert headers.len > 0
else:
  doAssert decision.remaining == 4
