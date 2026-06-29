import std/[times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/timeout

suite "timeout":
  test "is not expired before the duration elapses":
    let time = initManualTimeSource()
    let timeout = initTimeout(after = initDuration(seconds = 1), timeSource = time)

    check not timeout.expired()
    time.advance(initDuration(milliseconds = 999))
    check not timeout.expired()

  test "expires at the duration boundary":
    let time = initManualTimeSource()
    let timeout = initTimeout(after = initDuration(seconds = 1), timeSource = time)

    time.advance(initDuration(seconds = 1))

    check timeout.expired()

  test "reports elapsed time from construction":
    let time = initManualTimeSource()
    let timeout = initTimeout(after = initDuration(seconds = 5), timeSource = time)

    check timeout.elapsed() == initDuration()
    time.advance(initDuration(milliseconds = 750))
    check timeout.elapsed() == initDuration(milliseconds = 750)
    time.advance(initDuration(seconds = 2))
    check timeout.elapsed() == initDuration(milliseconds = 2750)

  test "reports remaining time capped at zero":
    let time = initManualTimeSource()
    let timeout = initTimeout(after = initDuration(seconds = 1), timeSource = time)

    check timeout.remaining() == initDuration(seconds = 1)
    time.advance(initDuration(milliseconds = 250))
    check timeout.remaining() == initDuration(milliseconds = 750)
    time.advance(initDuration(seconds = 2))
    check timeout.remaining() == initDuration()

  test "zero timeout is expired immediately":
    let time = initManualTimeSource()
    let timeout = initTimeout(after = initDuration(), timeSource = time)

    check timeout.expired()
    check timeout.elapsed() == initDuration()
    check timeout.remaining() == initDuration()

  test "rejects negative timeout durations":
    let time = initManualTimeSource()

    expect TimeoutConfigError:
      discard initTimeout(after = initDuration(milliseconds = -1), timeSource = time)

  test "default constructor uses a real time source":
    let timeout = initTimeout(after = initDuration(seconds = 1))

    check not timeout.expired()
