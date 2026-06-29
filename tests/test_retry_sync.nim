import std/[times, unittest]

import flowbrigade/[backoff, retry]

suite "sync retry":
  test "returns the operation result after a later success":
    var attempts = 0
    var slept: seq[Duration] = @[]
    let policy = fixedBackoff(initDuration(milliseconds = 100))

    proc recordSleep(delay: Duration) =
      slept.add(delay)

    proc operation(): int =
      inc attempts
      if attempts < 3:
        raise newException(IOError, "temporary")
      42

    let value = retry(
      policy = policy,
      maxAttempts = 3,
      sleep = recordSleep,
      operation = operation
    )

    check value == 42
    check attempts == 3
    check slept == @[
      initDuration(milliseconds = 100),
      initDuration(milliseconds = 100)
    ]

  test "raises the last exception after attempts are exhausted":
    var attempts = 0
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc noSleep(delay: Duration) =
      discard

    proc operation(): int =
      inc attempts
      raise newException(IOError, "still failing")

    expect IOError:
      discard retry(
        policy = policy,
        maxAttempts = 3,
        sleep = noSleep,
        operation = operation
      )

    check attempts == 3

  test "does not sleep after the final failed attempt":
    var sleeps = 0
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc countSleep(delay: Duration) =
      inc sleeps

    proc operation(): int =
      raise newException(IOError, "failure")

    expect IOError:
      discard retry(
        policy = policy,
        maxAttempts = 2,
        sleep = countSleep,
        operation = operation
      )

    check sleeps == 1

  test "does not retry when max attempts is one":
    var attempts = 0
    var sleeps = 0
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc countSleep(delay: Duration) =
      inc sleeps

    proc operation(): int =
      inc attempts
      raise newException(IOError, "failure")

    expect IOError:
      discard retry(
        policy = policy,
        maxAttempts = 1,
        sleep = countSleep,
        operation = operation
      )

    check attempts == 1
    check sleeps == 0

  test "rejects max attempts lower than one":
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc noSleep(delay: Duration) =
      discard

    proc operation(): int =
      1

    expect RetryConfigError:
      discard retry(
        policy = policy,
        maxAttempts = 0,
        sleep = noSleep,
        operation = operation
      )

  test "default retry overload uses built-in sleep":
    var attempts = 0
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc operation(): int =
      inc attempts
      7

    let value = retry(
      policy = policy,
      maxAttempts = 1,
      operation = operation
    )

    check value == 7
    check attempts == 1

  test "observer receives retry lifecycle events":
    var attempts = 0
    var events: seq[RetryEventKind] = @[]
    var delays: seq[Duration] = @[]
    let policy = fixedBackoff(initDuration(milliseconds = 10))

    proc noSleep(delay: Duration) =
      discard

    proc observe(event: RetryEvent) =
      events.add(event.kind)
      if event.delay > initDuration():
        delays.add(event.delay)

    proc operation(): int =
      inc attempts
      if attempts < 2:
        raise newException(IOError, "temporary")
      9

    let value = retry(
      policy = policy,
      maxAttempts = 2,
      sleep = noSleep,
      operation = operation,
      observer = observe
    )

    check value == 9
    check events == @[retryAttemptFailed, retrySleeping, retrySucceeded]
    check delays == @[initDuration(milliseconds = 10)]

  test "observer receives exhausted event":
    var events: seq[RetryEventKind] = @[]
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc noSleep(delay: Duration) =
      discard

    proc observe(event: RetryEvent) =
      events.add(event.kind)

    proc operation(): int =
      raise newException(IOError, "failure")

    expect IOError:
      discard retry(
        policy = policy,
        maxAttempts = 1,
        sleep = noSleep,
        operation = operation,
        observer = observe
      )

    check events == @[retryAttemptFailed, retryExhausted]

  test "propagates sleep failures":
    var attempts = 0
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc failingSleep(delay: Duration) =
      raise newException(OSError, "sleep failed")

    proc operation(): int =
      inc attempts
      raise newException(IOError, "operation failed")

    expect OSError:
      discard retry(
        policy = policy,
        maxAttempts = 3,
        sleep = failingSleep,
        operation = operation
      )

    check attempts == 1

  test "does not catch defects":
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc noSleep(delay: Duration) =
      discard

    proc operation(): int =
      raise newException(Defect, "programming error")

    expect Defect:
      discard retry(
        policy = policy,
        maxAttempts = 3,
        sleep = noSleep,
        operation = operation
      )
