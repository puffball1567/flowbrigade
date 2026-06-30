import std/[times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/ratelimit

suite "fixed window rate limiter":
  test "allows requests up to the limit in the current window":
    let time = initManualTimeSource()
    var limiter = initFixedWindow(
      limit = 2,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow()
    check limiter.allow()
    check not limiter.allow()

  test "resets when the next window starts":
    let time = initManualTimeSource()
    var limiter = initFixedWindow(
      limit = 2,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow()
    check limiter.allow()
    check not limiter.allow()

    time.advance(initDuration(seconds = 1))
    check limiter.allow()
    check limiter.allow()
    check not limiter.allow()

  test "does not reset before the window boundary":
    let time = initManualTimeSource()
    var limiter = initFixedWindow(
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow()
    time.advance(initDuration(milliseconds = 999))
    check not limiter.allow()

  test "supports custom request cost":
    let time = initManualTimeSource()
    var limiter = initFixedWindow(
      limit = 5,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow(cost = 3)
    check limiter.allow(cost = 2)
    check not limiter.allow()

  test "exposes fixed window configuration and usage":
    let time = initManualTimeSource()
    var limiter = initFixedWindow(
      limit = 5,
      per = initDuration(seconds = 10),
      timeSource = time
    )

    check limiter.configuredLimit() == 5
    check limiter.configuredPeriod() == initDuration(seconds = 10)
    check limiter.inUse() == 0

    check limiter.allow(cost = 3)
    check limiter.inUse() == 3

  test "reset clears fixed window usage":
    let time = initManualTimeSource()
    var limiter = initFixedWindow(
      limit = 2,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow(cost = 2)
    check limiter.inUse() == 2
    check not limiter.allow()
    limiter.reset()
    check limiter.inUse() == 0
    check limiter.allow(cost = 2)

  test "rejects invalid fixed window configuration":
    let time = initManualTimeSource()

    expect RateLimitConfigError:
      discard initFixedWindow(
        limit = 0,
        per = initDuration(seconds = 1),
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initFixedWindow(
        limit = 1,
        per = initDuration(),
        timeSource = time
      )

  test "rejects invalid fixed window cost":
    let time = initManualTimeSource()
    var limiter = initFixedWindow(
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    expect RateLimitError:
      discard limiter.allow(cost = 0)

    expect RateLimitError:
      discard limiter.allow(cost = -1)

  test "rejects costs above the window limit":
    let time = initManualTimeSource()
    var limiter = initFixedWindow(
      limit = 5,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    expect RateLimitError:
      discard limiter.allow(cost = 6)

  test "default constructor uses a real time source":
    var limiter = initFixedWindow(
      limit = 1,
      per = initDuration(seconds = 1)
    )

    check limiter.allow()
    check not limiter.allow()
