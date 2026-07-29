import std/[asyncdispatch, times, unittest]

import flowbrigade/[backoff, retry]
import flowbrigade/internal/time_source
import flowbrigade/timeout

suite "async retry":
  test "returns the async operation result after a later success":
    var attempts = 0
    var slept: seq[Duration] = @[]
    let policy = fixedBackoff(initDuration(milliseconds = 100))

    proc recordSleep(delay: Duration): Future[void] {.async.} =
      slept.add(delay)

    proc operation(): Future[int] {.async.} =
      inc attempts
      if attempts < 3:
        raise newException(IOError, "temporary")
      return 42

    let value = waitFor retryAsync(
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

  test "raises the last async exception after attempts are exhausted":
    var attempts = 0
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc noSleep(delay: Duration): Future[void] {.async.} =
      discard

    proc operation(): Future[int] {.async.} =
      inc attempts
      raise newException(IOError, "still failing")

    expect IOError:
      discard waitFor retryAsync(
        policy = policy,
        maxAttempts = 3,
        sleep = noSleep,
        operation = operation
      )

    check attempts == 3

  test "rejects invalid async max attempts":
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc noSleep(delay: Duration): Future[void] {.async.} =
      discard

    proc operation(): Future[int] {.async.} =
      return 1

    expect RetryConfigError:
      discard waitFor retryAsync(
        policy = policy,
        maxAttempts = 0,
        sleep = noSleep,
        operation = operation
      )

  test "default async retry overload uses sleepAsync":
    var attempts = 0
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc operation(): Future[int] {.async.} =
      inc attempts
      return 7

    let value = waitFor retryAsync(
      policy = policy,
      maxAttempts = 1,
      operation = operation
    )

    check value == 7
    check attempts == 1

  test "propagates async sleep failures":
    var attempts = 0
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc failingSleep(delay: Duration): Future[void] {.async.} =
      raise newException(OSError, "sleep failed")

    proc operation(): Future[int] {.async.} =
      inc attempts
      raise newException(IOError, "operation failed")

    expect OSError:
      discard waitFor retryAsync(
        policy = policy,
        maxAttempts = 3,
        sleep = failingSleep,
        operation = operation
      )

    check attempts == 1

  test "rethrows an error when the async retry condition rejects it":
    var attempts = 0
    var sleeps = 0
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc noSleep(delay: Duration): Future[void] {.async.} =
      discard delay
      inc sleeps

    proc operation(): Future[int] {.async.} =
      inc attempts
      raise newException(IOError, "not retryable")

    proc reject(error: ref CatchableError; attempt: int): bool =
      discard error
      discard attempt
      false

    expect IOError:
      discard waitFor retryAsync(
        policy = policy,
        maxAttempts = 3,
        sleep = noSleep,
        operation = operation,
        shouldRetry = reject
      )

    check attempts == 1
    check sleeps == 0

  test "does not retry cancellation errors by default":
    var attempts = 0
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc noSleep(delay: Duration): Future[void] {.async.} =
      discard delay

    proc operation(): Future[int] {.async.} =
      inc attempts
      raise newException(RetryCancelledError, "cancelled")

    expect RetryCancelledError:
      discard waitFor retryAsync(
        policy = policy,
        maxAttempts = 3,
        sleep = noSleep,
        operation = operation
      )

    check attempts == 1

  test "clamps the retry wait and expires before another attempt":
    let time = initManualTimeSource()
    let deadline = initDeadline(
      after = initDuration(milliseconds = 50),
      timeSource = time
    )
    let policy = fixedBackoff(initDuration(milliseconds = 100))
    var attempts = 0
    var sleeps: seq[Duration] = @[]

    proc advanceSleep(delay: Duration): Future[void] {.async.} =
      sleeps.add(delay)
      time.advance(delay)

    proc operation(): Future[int] {.async.} =
      inc attempts
      raise newException(IOError, "temporary")

    expect RetryDeadlineExceededError:
      discard waitFor retryAsync(
        policy = policy,
        maxAttempts = 3,
        sleep = advanceSleep,
        operation = operation,
        deadline = deadline
      )

    check attempts == 1
    check sleeps == @[initDuration(milliseconds = 50)]

  test "async observer receives retry lifecycle events in order":
    var attempts = 0
    var events: seq[RetryEventKind] = @[]
    let policy = fixedBackoff(initDuration(milliseconds = 1))

    proc noSleep(delay: Duration): Future[void] {.async.} =
      discard delay

    proc observe(event: RetryEvent) =
      events.add(event.kind)

    proc operation(): Future[int] {.async.} =
      inc attempts
      if attempts == 1:
        raise newException(IOError, "temporary")
      12

    let value = waitFor retryAsync(
      policy = policy,
      maxAttempts = 2,
      sleep = noSleep,
      operation = operation,
      observer = observe
    )
    check value == 12
    check events == @[retryAttemptFailed, retrySleeping, retrySucceeded]
