import std/[times, unittest]

import flowbrigade/backoff

suite "backoff jitter":
  test "no jitter leaves the delay unchanged":
    let policy = fixedBackoff(
      initDuration(milliseconds = 500),
      jitter = noJitter
    )

    check policy.delayFor(attempt = 1) == initDuration(milliseconds = 500)

  test "full jitter returns a delay from zero through the base delay":
    let policy = fixedBackoff(
      initDuration(seconds = 1),
      jitter = fullJitter
    )

    for attempt in 1 .. 20:
      let delay = policy.delayFor(attempt)
      check delay >= initDuration()
      check delay <= initDuration(seconds = 1)

  test "equal jitter returns a delay from half through the base delay":
    let policy = fixedBackoff(
      initDuration(seconds = 1),
      jitter = equalJitter
    )

    for attempt in 1 .. 20:
      let delay = policy.delayFor(attempt)
      check delay >= initDuration(milliseconds = 500)
      check delay <= initDuration(seconds = 1)

  test "decorrelated jitter stays within configured bounds":
    let policy = expBackoff(
      initial = initDuration(milliseconds = 100),
      factor = 2.0,
      maxDelay = initDuration(seconds = 2),
      jitter = decorrelatedJitter
    )

    for attempt in 1 .. 20:
      let delay = policy.delayFor(attempt)
      check delay >= initDuration(milliseconds = 100)
      check delay <= initDuration(seconds = 2)

  test "decorrelated jitter retains the prior delay and accepts an injected source":
    proc highest(upperExclusive: int64): int64 =
      upperExclusive - 1

    let policy = expBackoff(
      initial = initDuration(milliseconds = 100),
      factor = 2.0,
      maxDelay = initDuration(seconds = 2),
      jitter = decorrelatedJitter,
      randomSource = highest
    )

    check policy.delayFor(attempt = 1) == initDuration(milliseconds = 300)
    check policy.delayFor(attempt = 2) == initDuration(milliseconds = 900)
    policy.resetJitter()
    check policy.delayFor(attempt = 1) == initDuration(milliseconds = 300)
