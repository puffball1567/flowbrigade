import std/[times, unittest]

import flowbrigade/ratelimit

suite "rate limit exception helpers":
  test "raiseIfDenied does nothing for allowed decisions":
    let decision = allowedResult(
      limit = 10,
      remaining = 9,
      resetAfter = initDuration(minutes = 1)
    )

    decision.raiseIfDenied()

  test "raiseIfDenied raises with decision metadata":
    let decision = deniedResult(
      limit = 10,
      remaining = 0,
      retryAfter = initDuration(seconds = 30),
      resetAfter = initDuration(minutes = 1)
    )

    try:
      decision.raiseIfDenied()
      fail()
    except RateLimitExceededError as exc:
      check exc.decision.limit == 10
      check exc.decision.retryAfter == initDuration(seconds = 30)

  test "remainingOrRaise returns remaining count":
    let decision = allowedResult(
      limit = 10,
      remaining = 4,
      resetAfter = initDuration(minutes = 1)
    )

    check decision.remainingOrRaise() == 4

  test "remainingOrRaise raises for denied decisions":
    let decision = deniedResult(
      limit = 10,
      remaining = 0,
      retryAfter = initDuration(seconds = 30),
      resetAfter = initDuration(minutes = 1)
    )

    expect RateLimitExceededError:
      discard decision.remainingOrRaise()
