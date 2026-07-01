import std/[times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/ratelimit

suite "GCRA rate limiter":
  test "allows requests up to burst capacity":
    let time = initManualTimeSource()
    var limiter = initGcraLimiter(
      rate = 2,
      per = initDuration(seconds = 1),
      burst = 2,
      timeSource = time
    )

    check limiter.allow()
    check limiter.allow()
    let denied = limiter.consume()
    check not denied.allowed
    check denied.retryAfter == initDuration(milliseconds = 500)

  test "smoothly allows after the theoretical interval":
    let time = initManualTimeSource()
    var limiter = initGcraLimiter(
      rate = 2,
      per = initDuration(seconds = 1),
      burst = 2,
      timeSource = time
    )

    check limiter.allow()
    check limiter.allow()
    check not limiter.allow()

    time.advance(initDuration(milliseconds = 499))
    check not limiter.allow()

    time.advance(initDuration(milliseconds = 1))
    check limiter.allow()
    check not limiter.allow()

  test "does not build unlimited credit after idle time":
    let time = initManualTimeSource()
    var limiter = initGcraLimiter(
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 3,
      timeSource = time
    )

    time.advance(initDuration(seconds = 10))
    check limiter.allow(cost = 3)
    check not limiter.allow()

  test "supports custom cost and reports remaining capacity":
    let time = initManualTimeSource()
    var limiter = initGcraLimiter(
      rate = 10,
      per = initDuration(seconds = 1),
      burst = 10,
      timeSource = time
    )

    let first = limiter.consume(cost = 4)
    check first.allowed
    check first.remaining == 6

    let second = limiter.consume(cost = 6)
    check second.allowed
    check second.remaining == 0

    let denied = limiter.consume()
    check not denied.allowed
    check denied.remaining == 0
    check denied.retryAfter == initDuration(milliseconds = 100)

  test "inspect does not consume capacity":
    let time = initManualTimeSource()
    var limiter = initGcraLimiter(
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1,
      timeSource = time
    )

    check limiter.inspect().allowed
    check limiter.inspect().allowed
    check limiter.allow()
    check not limiter.allow()

  test "reset restores full burst capacity":
    let time = initManualTimeSource()
    var limiter = initGcraLimiter(
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 2,
      timeSource = time
    )

    check limiter.allow(cost = 2)
    check not limiter.allow()
    limiter.reset()
    check limiter.availableCapacity() == 2
    check limiter.allow(cost = 2)

  test "exposes GCRA configuration":
    let time = initManualTimeSource()
    let limiter = initGcraLimiter(
      rate = 4,
      per = initDuration(seconds = 2),
      burst = 3,
      timeSource = time
    )

    check limiter.configuredRate() == 4
    check limiter.configuredPeriod() == initDuration(seconds = 2)
    check limiter.configuredBurst() == 3
    check limiter.configuredInterval() == initDuration(milliseconds = 500)
    check limiter.availableCapacity() == 3

  test "rounds fractional intervals up to avoid over-allowing":
    let time = initManualTimeSource()
    var limiter = initGcraLimiter(
      rate = 3,
      per = initDuration(seconds = 1),
      burst = 1,
      timeSource = time
    )

    check limiter.configuredInterval() == initDuration(nanoseconds = 333_333_334)
    check limiter.allow()
    time.advance(initDuration(nanoseconds = 333_333_333))
    check not limiter.allow()
    time.advance(initDuration(nanoseconds = 1))
    check limiter.allow()

  test "rejects invalid GCRA configuration and costs":
    let time = initManualTimeSource()

    expect RateLimitConfigError:
      discard initGcraLimiter(0, initDuration(seconds = 1), 1, time)
    expect RateLimitConfigError:
      discard initGcraLimiter(1, initDuration(), 1, time)
    expect RateLimitConfigError:
      discard initGcraLimiter(1, initDuration(seconds = 1), 0, time)
    expect RateLimitConfigError:
      discard initGcraLimiter(1, initDuration(seconds = 1), 1, nil)

    var limiter = initGcraLimiter(1, initDuration(seconds = 1), 1, time)
    expect RateLimitError:
      discard limiter.consume(cost = 0)
    expect RateLimitError:
      discard limiter.consume(cost = 2)

  test "default constructor uses a real time source":
    var limiter = initGcraLimiter(
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1
    )

    check limiter.allow()
    check not limiter.allow()

suite "keyed GCRA rate limiter":
  test "tracks limits independently for each key":
    let time = initManualTimeSource()
    var limiter = initKeyedGcraLimiter[string](
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1,
      timeSource = time
    )

    check limiter.allow("alice")
    check not limiter.allow("alice")
    check limiter.allow("bob")
    check not limiter.allow("bob")

  test "supports non-string keys":
    let time = initManualTimeSource()
    var limiter = initKeyedGcraLimiter[int](
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1,
      timeSource = time
    )

    check limiter.allow(1001)
    check not limiter.allow(1001)
    check limiter.allow(1002)

  test "keyed inspect does not retain new keys":
    let time = initManualTimeSource()
    var limiter = initKeyedGcraLimiter[string](
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1,
      timeSource = time
    )

    check limiter.inspect("alice").allowed
    check limiter.activeKeys() == 0

  test "clear and reset free keyed GCRA capacity":
    let time = initManualTimeSource()
    var limiter = initKeyedGcraLimiter[string](
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1,
      timeSource = time,
      maxKeys = 1
    )

    check limiter.allow("alice")
    expect RateLimitError:
      discard limiter.allow("bob")

    check limiter.clear("alice")
    check not limiter.clear("alice")
    check limiter.allow("bob")
    check limiter.reset("bob")
    check limiter.activeKeys() == 0

  test "resetAll clears keyed GCRA state":
    let time = initManualTimeSource()
    var limiter = initKeyedGcraLimiter[string](
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1,
      timeSource = time
    )

    check limiter.allow("alice")
    check limiter.allow("bob")
    check limiter.activeKeys() == 2
    check limiter.resetAll() == 2
    check limiter.activeKeys() == 0

  test "prunes idle keys before enforcing capacity":
    let time = initManualTimeSource()
    var limiter = initKeyedGcraLimiter[string](
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1,
      timeSource = time,
      maxKeys = 1
    )

    check limiter.allow("alice")
    expect RateLimitError:
      discard limiter.allow("bob")

    time.advance(initDuration(seconds = 1))
    check limiter.allow("bob")

  test "rejects unsafe keyed GCRA inputs":
    let time = initManualTimeSource()
    var limiter = initKeyedGcraLimiter[string](
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1,
      timeSource = time
    )

    expect RateLimitError:
      discard limiter.inspect("")
    expect RateLimitError:
      discard limiter.consume(" ")
    expect RateLimitError:
      discard limiter.allow("tenant" & chr(10))
    expect RateLimitError:
      discard limiter.allow("alice", cost = 0)
    expect RateLimitError:
      discard limiter.allow("alice", cost = 2)

  test "exposes keyed GCRA configuration":
    let time = initManualTimeSource()
    var limiter = initKeyedGcraLimiter[string](
      rate = 2,
      per = initDuration(seconds = 1),
      burst = 3,
      timeSource = time,
      maxKeys = 5
    )

    check limiter.configuredRate() == 2
    check limiter.configuredPeriod() == initDuration(seconds = 1)
    check limiter.configuredBurst() == 3
    check limiter.configuredInterval() == initDuration(milliseconds = 500)
    check limiter.keyCapacity() == 5
    check limiter.activeKeys() == 0

  test "rejects invalid keyed GCRA configuration":
    let time = initManualTimeSource()

    expect RateLimitConfigError:
      discard initKeyedGcraLimiter[string](0, initDuration(seconds = 1), 1, time)
    expect RateLimitConfigError:
      discard initKeyedGcraLimiter[string](1, initDuration(), 1, time)
    expect RateLimitConfigError:
      discard initKeyedGcraLimiter[string](1, initDuration(seconds = 1), 0, time)
    expect RateLimitConfigError:
      discard initKeyedGcraLimiter[string](1, initDuration(seconds = 1), 1, time, maxKeys = 0)
    expect RateLimitConfigError:
      discard initKeyedGcraLimiter[string](1, initDuration(seconds = 1), 1, nil)
