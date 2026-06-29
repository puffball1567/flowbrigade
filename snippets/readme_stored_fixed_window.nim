import std/times

import flowbrigade

let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
let limiter = initStoredFixedWindow(
  prefix = "api",
  limit = 100,
  per = initDuration(minutes = 1),
  storage = storage
)

let decision = limiter.consume("user:42")
doAssert decision.allowed
