import std/[times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/ratelimit

suite "compound rate limiter":
  test "allows when every rule allows":
    let time = initManualTimeSource()
    var shortLimit = initFixedWindow(
      limit = 2,
      per = initDuration(seconds = 1),
      timeSource = time
    )
    var burstLimit = initTokenBucket(
      rate = 10,
      per = initDuration(seconds = 1),
      burst = 10,
      timeSource = time
    )

    let limiter = initCompoundLimiter([
      rateLimitRule(
        "short",
        proc(): RateLimitResult = shortLimit.inspect(),
        proc(): RateLimitResult = shortLimit.consume()
      ),
      rateLimitRule(
        "burst",
        proc(): RateLimitResult = burstLimit.inspect(),
        proc(): RateLimitResult = burstLimit.consume()
      )
    ])

    let allowed = limiter.consume()
    check allowed.allowed
    check allowed.limit == 2
    check allowed.remaining == 1
    check shortLimit.allow()
    check not shortLimit.allow()

  test "denies when any rule denies":
    let time = initManualTimeSource()
    var strictLimit = initFixedWindow(
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )
    var looseLimit = initFixedWindow(
      limit = 10,
      per = initDuration(seconds = 10),
      timeSource = time
    )

    discard strictLimit.consume()

    let limiter = initCompoundLimiter([
      rateLimitRule(
        "strict",
        proc(): RateLimitResult = strictLimit.inspect(),
        proc(): RateLimitResult = strictLimit.consume()
      ),
      rateLimitRule(
        "loose",
        proc(): RateLimitResult = looseLimit.inspect(),
        proc(): RateLimitResult = looseLimit.consume()
      )
    ])

    let denied = limiter.consume()
    check not denied.allowed
    check denied.limit == 1
    check denied.remaining == 0
    check denied.retryAfter == initDuration(seconds = 1)

  test "does not consume any rule when inspection denies":
    let time = initManualTimeSource()
    var deniedLimit = initFixedWindow(
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )
    var availableLimit = initFixedWindow(
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    discard deniedLimit.consume()

    let limiter = initCompoundLimiter([
      rateLimitRule(
        "denied",
        proc(): RateLimitResult = deniedLimit.inspect(),
        proc(): RateLimitResult = deniedLimit.consume()
      ),
      rateLimitRule(
        "available",
        proc(): RateLimitResult = availableLimit.inspect(),
        proc(): RateLimitResult = availableLimit.consume()
      )
    ])

    check not limiter.allow()
    check availableLimit.allow()
    check not availableLimit.allow()

  test "inspect does not consume nested rules":
    let time = initManualTimeSource()
    var fixed = initFixedWindow(
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )
    var sliding = initSlidingWindow(
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    let limiter = initCompoundLimiter([
      rateLimitRule(
        "fixed",
        proc(): RateLimitResult = fixed.inspect(),
        proc(): RateLimitResult = fixed.consume()
      ),
      rateLimitRule(
        "sliding",
        proc(): RateLimitResult = sliding.inspect(),
        proc(): RateLimitResult = sliding.consume()
      )
    ])

    check limiter.inspect().allowed
    check limiter.inspect().allowed
    check limiter.allow()
    check not limiter.allow()

  test "uses the longest retry delay across denied rules":
    let time = initManualTimeSource()
    var shortLimit = initFixedWindow(
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )
    var longLimit = initFixedWindow(
      limit = 1,
      per = initDuration(seconds = 10),
      timeSource = time
    )

    discard shortLimit.consume()
    discard longLimit.consume()

    let limiter = initCompoundLimiter([
      rateLimitRule(
        "short",
        proc(): RateLimitResult = shortLimit.inspect(),
        proc(): RateLimitResult = shortLimit.consume()
      ),
      rateLimitRule(
        "long",
        proc(): RateLimitResult = longLimit.inspect(),
        proc(): RateLimitResult = longLimit.consume()
      )
    ])

    let denied = limiter.inspect()
    check not denied.allowed
    check denied.retryAfter == initDuration(seconds = 10)
    check denied.resetAfter == initDuration(seconds = 10)

  test "rejects invalid compound configuration":
    expect RateLimitConfigError:
      discard initCompoundLimiter([])

    expect RateLimitConfigError:
      discard rateLimitRule(
        "missing-inspect",
        nil,
        proc(): RateLimitResult = allowedResult(1, 0, initDuration(seconds = 1))
      )

    expect RateLimitConfigError:
      discard rateLimitRule(
        "missing-consume",
        proc(): RateLimitResult = allowedResult(1, 0, initDuration(seconds = 1)),
        nil
      )
