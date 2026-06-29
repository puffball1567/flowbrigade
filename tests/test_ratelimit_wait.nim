import std/[asyncdispatch, times, unittest]

import flowbrigade/ratelimit

suite "rate limit wait helpers":
  test "wait does nothing for allowed results":
    var slept = initDuration()
    let decision = allowedResult(
      limit = 1,
      remaining = 0,
      resetAfter = initDuration(seconds = 1)
    )

    decision.wait(proc(delay: Duration) = slept = delay)
    check slept == initDuration()

  test "wait sleeps retry delay for denied results":
    var slept = initDuration()
    let decision = deniedResult(
      limit = 1,
      remaining = 0,
      retryAfter = initDuration(milliseconds = 250),
      resetAfter = initDuration(seconds = 1)
    )

    decision.wait(proc(delay: Duration) = slept = delay)
    check slept == initDuration(milliseconds = 250)

  test "wait rejects nil sleep proc":
    let decision = deniedResult(
      limit = 1,
      remaining = 0,
      retryAfter = initDuration(milliseconds = 250),
      resetAfter = initDuration(seconds = 1)
    )

    expect ValueError:
      decision.wait(nil)

  test "waitAsync sleeps retry delay":
    proc scenario() {.async.} =
      var slept = initDuration()
      let decision = deniedResult(
        limit = 1,
        remaining = 0,
        retryAfter = initDuration(milliseconds = 250),
        resetAfter = initDuration(seconds = 1)
      )

      await decision.waitAsync(proc(delay: Duration): Future[void] {.async.} =
        slept = delay
      )
      check slept == initDuration(milliseconds = 250)

    waitFor scenario()
