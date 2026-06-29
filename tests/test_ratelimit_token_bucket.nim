import std/[times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/ratelimit

suite "token bucket rate limiter":
  test "allows requests up to burst capacity":
    let time = initManualTimeSource()
    var limiter = initTokenBucket(
      rate = 2,
      per = initDuration(seconds = 1),
      burst = 2,
      timeSource = time
    )

    check limiter.allow()
    check limiter.allow()
    check not limiter.allow()

  test "refills tokens as time advances":
    let time = initManualTimeSource()
    var limiter = initTokenBucket(
      rate = 2,
      per = initDuration(seconds = 1),
      burst = 2,
      timeSource = time
    )

    check limiter.allow()
    check limiter.allow()
    check not limiter.allow()

    time.advance(initDuration(milliseconds = 500))
    check limiter.allow()
    check not limiter.allow()

  test "does not refill beyond burst capacity":
    let time = initManualTimeSource()
    var limiter = initTokenBucket(
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 3,
      timeSource = time
    )

    time.advance(initDuration(seconds = 10))

    check limiter.allow(cost = 3)
    check not limiter.allow()

  test "supports custom token cost":
    let time = initManualTimeSource()
    var limiter = initTokenBucket(
      rate = 10,
      per = initDuration(seconds = 1),
      burst = 10,
      timeSource = time
    )

    check limiter.allow(cost = 4)
    check limiter.allow(cost = 6)
    check not limiter.allow()

  test "rejects invalid token bucket configuration":
    let time = initManualTimeSource()

    expect RateLimitConfigError:
      discard initTokenBucket(
        rate = 0,
        per = initDuration(seconds = 1),
        burst = 1,
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initTokenBucket(
        rate = 1,
        per = initDuration(),
        burst = 1,
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initTokenBucket(
        rate = 1,
        per = initDuration(seconds = 1),
        burst = 0,
        timeSource = time
      )

  test "rejects invalid token cost":
    let time = initManualTimeSource()
    var limiter = initTokenBucket(
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1,
      timeSource = time
    )

    expect RateLimitError:
      discard limiter.allow(cost = 0)

    expect RateLimitError:
      discard limiter.allow(cost = -1)

  test "rejects costs above burst capacity":
    let time = initManualTimeSource()
    var limiter = initTokenBucket(
      rate = 10,
      per = initDuration(seconds = 1),
      burst = 5,
      timeSource = time
    )

    expect RateLimitError:
      discard limiter.allow(cost = 6)

  test "default constructor uses a real time source":
    var limiter = initTokenBucket(
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1
    )

    check limiter.allow()
    check not limiter.allow()
