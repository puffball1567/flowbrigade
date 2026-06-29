import std/[times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/ratelimit

suite "keyed in-memory rate limiter":
  test "tracks limits independently for each key":
    let time = initManualTimeSource()
    var limiter = initKeyedFixedWindow[string](
      limit = 2,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow("alice")
    check limiter.allow("alice")
    check not limiter.allow("alice")

    check limiter.allow("bob")
    check limiter.allow("bob")
    check not limiter.allow("bob")

  test "resets each key when the next window starts":
    let time = initManualTimeSource()
    var limiter = initKeyedFixedWindow[string](
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow("job-a")
    check not limiter.allow("job-a")

    time.advance(initDuration(seconds = 1))
    check limiter.allow("job-a")

  test "supports non-string keys":
    let time = initManualTimeSource()
    var limiter = initKeyedFixedWindow[int](
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow(1001)
    check not limiter.allow(1001)
    check limiter.allow(1002)

  test "supports custom request cost per key":
    let time = initManualTimeSource()
    var limiter = initKeyedFixedWindow[string](
      limit = 5,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.allow("alice", cost = 3)
    check limiter.allow("alice", cost = 2)
    check not limiter.allow("alice")
    check limiter.allow("bob", cost = 5)

  test "rejects invalid keyed fixed window configuration":
    let time = initManualTimeSource()

    expect RateLimitConfigError:
      discard initKeyedFixedWindow[string](
        limit = 0,
        per = initDuration(seconds = 1),
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initKeyedFixedWindow[string](
        limit = 1,
        per = initDuration(),
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initKeyedFixedWindow[string](
        limit = 1,
        per = initDuration(seconds = 1),
        timeSource = time,
        maxKeys = 0
      )

  test "rejects invalid keyed cost":
    let time = initManualTimeSource()
    var limiter = initKeyedFixedWindow[string](
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    expect RateLimitError:
      discard limiter.allow("alice", cost = 0)

    expect RateLimitError:
      discard limiter.allow("alice", cost = -1)

  test "rejects keyed costs above the window limit":
    let time = initManualTimeSource()
    var limiter = initKeyedFixedWindow[string](
      limit = 5,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    expect RateLimitError:
      discard limiter.allow("alice", cost = 6)

  test "default constructor uses a real time source":
    var limiter = initKeyedFixedWindow[string](
      limit = 1,
      per = initDuration(seconds = 1)
    )

    check limiter.allow("alice")
    check not limiter.allow("alice")

  test "rejects new keys when max key capacity is reached":
    let time = initManualTimeSource()
    var limiter = initKeyedFixedWindow[string](
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time,
      maxKeys = 2
    )

    check limiter.allow("alice")
    check limiter.allow("bob")

    expect RateLimitError:
      discard limiter.allow("carol")

  test "prunes expired keys before enforcing max key capacity":
    let time = initManualTimeSource()
    var limiter = initKeyedFixedWindow[string](
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time,
      maxKeys = 2
    )

    check limiter.allow("alice")
    check limiter.allow("bob")

    time.advance(initDuration(seconds = 1))

    check limiter.allow("carol")
