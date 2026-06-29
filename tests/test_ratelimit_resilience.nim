import std/[times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/ratelimit

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

suite "rate limit storage resilience":
  test "fail closed denies when storage fails":
    let storage = failingStorage().withStorageFailureMode(failClosed)
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 10,
      per = initDuration(seconds = 5),
      storage = storage,
      timeSource = initManualTimeSource()
    )

    let decision = limiter.consume("alice")
    check not decision.allowed
    check decision.remaining == 0
    check decision.retryAfter == initDuration(seconds = 5)

  test "fail open allows when storage fails":
    let storage = failingStorage().withStorageFailureMode(failOpen)
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 10,
      per = initDuration(seconds = 5),
      storage = storage,
      timeSource = initManualTimeSource()
    )

    let decision = limiter.consume("alice", cost = 3)
    check decision.allowed
    check decision.remaining == 7
    check decision.resetAfter == initDuration(seconds = 5)

  test "clear returns false when storage fails":
    let storage = failingStorage().withStorageFailureMode(failOpen)
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 10,
      per = initDuration(seconds = 5),
      storage = storage,
      timeSource = initManualTimeSource()
    )

    check not limiter.clear("alice")

  test "rejects invalid wrapped storage":
    expect RateLimitConfigError:
      discard RateLimitStorage().withStorageFailureMode(failClosed)
