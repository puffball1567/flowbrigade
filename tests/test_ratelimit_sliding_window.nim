import std/[times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/ratelimit

suite "sliding window rate limiter":
  test "allows requests up to the limit in the active window":
    let time = initManualTimeSource()
    var limiter = initSlidingWindow(
      limit = 2,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow()
    check limiter.allow()
    check not limiter.allow()

  test "weights the previous window across the boundary":
    let time = initManualTimeSource()
    var limiter = initSlidingWindow(
      limit = 10,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow(cost = 10)
    time.advance(initDuration(milliseconds = 100))
    check not limiter.allow()

    time.advance(initDuration(milliseconds = 900))
    let atBoundary = limiter.inspect(cost = 1)
    check not atBoundary.allowed
    check atBoundary.remaining == 0

    time.advance(initDuration(milliseconds = 500))
    let halfway = limiter.inspect(cost = 5)
    check halfway.allowed
    check halfway.remaining == 0

  test "forgets old windows after a full quiet period":
    let time = initManualTimeSource()
    var limiter = initSlidingWindow(
      limit = 3,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow(cost = 3)
    time.advance(initDuration(seconds = 2))
    check limiter.allow(cost = 3)
    check not limiter.allow()

  test "supports custom request cost":
    let time = initManualTimeSource()
    var limiter = initSlidingWindow(
      limit = 5,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow(cost = 3)
    check limiter.allow(cost = 2)
    check not limiter.allow()

  test "consume returns retry timing when denied":
    let time = initManualTimeSource()
    var limiter = initSlidingWindow(
      limit = 10,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    discard limiter.consume(cost = 10)
    time.advance(initDuration(seconds = 1))
    let denied = limiter.consume(cost = 1)
    check not denied.allowed
    check denied.retryAfter == initDuration(milliseconds = 100)
    check denied.resetAfter == initDuration(seconds = 1)

  test "inspect does not consume capacity":
    let time = initManualTimeSource()
    var limiter = initSlidingWindow(
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.inspect().allowed
    check limiter.inspect().allowed
    check limiter.allow()
    check not limiter.allow()

  test "rejects invalid sliding window configuration":
    let time = initManualTimeSource()

    expect RateLimitConfigError:
      discard initSlidingWindow(
        limit = 0,
        per = initDuration(seconds = 1),
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initSlidingWindow(
        limit = 1,
        per = initDuration(),
        timeSource = time
      )

  test "rejects invalid sliding window costs":
    let time = initManualTimeSource()
    var limiter = initSlidingWindow(
      limit = 2,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    expect RateLimitError:
      discard limiter.allow(cost = 0)
    expect RateLimitError:
      discard limiter.inspect(cost = -1)
    expect RateLimitError:
      discard limiter.consume(cost = 3)

  test "default constructor uses a real time source":
    var limiter = initSlidingWindow(
      limit = 1,
      per = initDuration(seconds = 1)
    )

    check limiter.allow()
    check not limiter.allow()
