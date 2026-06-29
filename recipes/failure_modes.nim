import std/times

import flowbrigade

proc failingStorage(): RateLimitStorage =
  RateLimitStorage(
    inspectFixedWindow: proc(
      key: string;
      limit: int;
      per: Duration;
      cost: int;
      current: Duration
    ): RateLimitResult =
      raise newException(IOError, "storage unavailable"),
    consumeFixedWindow: proc(
      key: string;
      limit: int;
      per: Duration;
      cost: int;
      current: Duration
    ): RateLimitResult =
      raise newException(IOError, "storage unavailable"),
    clearFixedWindow: proc(key: string): bool =
      raise newException(IOError, "storage unavailable")
  )

let closedLimiter = initStoredFixedWindow(
  prefix = "login",
  limit = 5,
  per = 1.min,
  storage = failingStorage().withStorageFailureMode(failClosed)
)

let closedDecision = closedLimiter.consume("user:42")
doAssert not closedDecision.allowed
doAssert closedDecision.retryAfter == 1.min
doAssert not closedLimiter.clear("user:42")

let openLimiter = initStoredFixedWindow(
  prefix = "metrics",
  limit = 5,
  per = 1.min,
  storage = failingStorage().withStorageFailureMode(failOpen)
)

let openDecision = openLimiter.consume("heartbeat")
doAssert openDecision.allowed
doAssert openDecision.remaining == 4
doAssert not openLimiter.clear("heartbeat")
