import std/[asyncdispatch, times, unittest]

import flowbrigade/ratelimit

suite "rate limit reservations":
  test "accepts allowed decisions immediately":
    let decision = allowedResult(
      limit = 10,
      remaining = 9,
      resetAfter = initDuration(minutes = 1)
    )

    let reservation = decision.reserve()

    check reservation.accepted
    check reservation.readyAfter == initDuration()

  test "accepts denied decisions within max wait":
    let decision = deniedResult(
      limit = 10,
      remaining = 0,
      retryAfter = initDuration(seconds = 5),
      resetAfter = initDuration(minutes = 1)
    )

    let reservation = decision.reserve(maxWait = initDuration(seconds = 10))

    check reservation.accepted
    check reservation.readyAfter == initDuration(seconds = 5)

  test "rejects denied decisions beyond max wait":
    let decision = deniedResult(
      limit = 10,
      remaining = 0,
      retryAfter = initDuration(seconds = 30),
      resetAfter = initDuration(minutes = 1)
    )

    let reservation = decision.reserve(maxWait = initDuration(seconds = 10))

    check not reservation.accepted
    expect RateLimitError:
      reservation.raiseIfRejected()

  test "wait uses reservation delay":
    let decision = deniedResult(
      limit = 10,
      remaining = 0,
      retryAfter = initDuration(seconds = 5),
      resetAfter = initDuration(minutes = 1)
    )
    let reservation = decision.reserve(maxWait = initDuration(seconds = 10))
    var slept = initDuration()

    reservation.wait(proc(delay: Duration) =
      slept = delay
    )

    check slept == initDuration(seconds = 5)

  test "wait rejects reservations beyond max wait":
    let decision = deniedResult(
      limit = 10,
      remaining = 0,
      retryAfter = initDuration(seconds = 30),
      resetAfter = initDuration(minutes = 1)
    )
    let reservation = decision.reserve(maxWait = initDuration(seconds = 10))

    expect RateLimitError:
      reservation.wait(proc(delay: Duration) = discard)

  test "async wait uses reservation delay":
    proc scenario() {.async.} =
      let decision = deniedResult(
        limit = 10,
        remaining = 0,
        retryAfter = initDuration(seconds = 5),
        resetAfter = initDuration(minutes = 1)
      )
      let reservation = decision.reserve(maxWait = initDuration(seconds = 10))
      var slept = initDuration()

      await reservation.waitAsync(proc(delay: Duration): Future[void] {.async.} =
        slept = delay
      )

      check slept == initDuration(seconds = 5)

    waitFor scenario()
