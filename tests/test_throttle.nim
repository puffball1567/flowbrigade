import std/[times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/throttle

suite "throttle":
  test "allows the first action immediately":
    let time = initManualTimeSource()
    var throttle = initThrottle(every = initDuration(seconds = 1), timeSource = time)

    check throttle.allow()

  test "blocks repeated actions before the interval elapses":
    let time = initManualTimeSource()
    var throttle = initThrottle(every = initDuration(seconds = 1), timeSource = time)

    check throttle.allow()
    check not throttle.allow()
    time.advance(initDuration(milliseconds = 999))
    check not throttle.allow()

  test "allows again at the interval boundary":
    let time = initManualTimeSource()
    var throttle = initThrottle(every = initDuration(seconds = 1), timeSource = time)

    check throttle.allow()
    time.advance(initDuration(seconds = 1))
    check throttle.allow()

  test "can be reset":
    let time = initManualTimeSource()
    var throttle = initThrottle(every = initDuration(seconds = 1), timeSource = time)

    check throttle.allow()
    throttle.reset()
    check throttle.allow()

  test "rejects invalid throttle intervals":
    let time = initManualTimeSource()

    expect ThrottleConfigError:
      discard initThrottle(every = initDuration(), timeSource = time)

  test "default constructor uses a real time source":
    var throttle = initThrottle(every = initDuration(seconds = 1))

    check throttle.allow()
    check not throttle.allow()
