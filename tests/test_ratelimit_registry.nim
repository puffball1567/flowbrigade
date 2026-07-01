import std/[times, unittest]

import flowbrigade/ratelimit

suite "limiter registry":
  test "registers and consumes named fixed window limiters":
    var registry = initLimiterRegistry()
    registry.addLimiter("global", fixedWindowDefinition(limit = 1, per = initDuration(minutes = 1)))

    check registry.hasLimiter("global")
    check registry.allow("global")
    check not registry.allow("global")

  test "registers keyed fixed window limiters":
    var registry = initLimiterRegistry()
    registry.addLimiter("login", keyedFixedWindowDefinition(
      limit = 1,
      per = initDuration(minutes = 1)
    ))

    check registry.allow("login", key = "user:1")
    check not registry.allow("login", key = "user:1")
    check registry.allow("login", key = "user:2")
    check registry.clear("login", key = "user:1")
    check registry.allow("login", key = "user:1")
    check not registry.clear("login", key = "user:missing")

  test "registers token bucket limiters":
    var registry = initLimiterRegistry()
    registry.addLimiter("burst", tokenBucketDefinition(
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1
    ))

    check registry.allow("burst")
    check not registry.allow("burst")

  test "registers stored fixed window limiters":
    var registry = initLimiterRegistry()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
    registry.addStoredFixedWindow(
      name = "stored",
      prefix = "api",
      limit = 1,
      per = initDuration(minutes = 1),
      storage = storage
    )

    check registry.allow("stored", key = "user:1")
    check not registry.allow("stored", key = "user:1")
    check registry.clear("stored", key = "user:1")
    check registry.allow("stored", key = "user:1")

  test "registers compound limiters from named children":
    var registry = initLimiterRegistry()
    registry.addLimiter("per_minute", keyedFixedWindowDefinition(
      limit = 2,
      per = initDuration(minutes = 1)
    ))
    registry.addLimiter("per_hour", keyedFixedWindowDefinition(
      limit = 3,
      per = initDuration(hours = 1)
    ))
    registry.addCompoundLimiter("contact", ["per_minute", "per_hour"])

    check registry.allow("contact", key = "user:1")
    check registry.allow("contact", key = "user:1")
    check not registry.allow("contact", key = "user:1")
    check registry.allow("contact", key = "user:2")

  test "rejects invalid registry use":
    var registry = initLimiterRegistry()

    expect RateLimitConfigError:
      registry.addLimiter("", fixedWindowDefinition(limit = 1, per = initDuration(minutes = 1)))

    registry.addLimiter("global", fixedWindowDefinition(limit = 1, per = initDuration(minutes = 1)))

    expect RateLimitConfigError:
      registry.addLimiter("global", fixedWindowDefinition(limit = 1, per = initDuration(minutes = 1)))
    expect RateLimitError:
      discard registry.consume("missing")
    expect RateLimitConfigError:
      registry.addCompoundLimiter("empty", [])
    expect RateLimitError:
      discard registry.consume("global", cost = 0)

  test "accepts custom limiter handles":
    var registry = initLimiterRegistry()
    var used = false
    registry.addLimiter("custom", LimiterHandle(
      inspect: proc(key: string; cost: int): RateLimitResult =
        allowedResult(limit = 1, remaining = if used: 0 else: 1, resetAfter = initDuration(minutes = 1)),
      consume: proc(key: string; cost: int): RateLimitResult =
        used = true
        allowedResult(limit = 1, remaining = 0, resetAfter = initDuration(minutes = 1)),
      clear: proc(key: string): bool =
        used = false
        true
    ))

    check registry.inspect("custom").remaining == 1
    check registry.consume("custom").remaining == 0
    check registry.clear("custom")
    check registry.inspect("custom").remaining == 1
