import std/[asyncdispatch, times]

import ../backoff
import ./errors

type
  AsyncSleepProc* = proc(delay: Duration): Future[void] {.closure.}

proc sleepDurationAsync*(delay: Duration): Future[void] {.async.} =
  ## Sleeps asynchronously for a Nim `Duration`, rounding sub-millisecond delays up.
  let nanos = delay.inNanoseconds
  if nanos <= 0:
    return
  await sleepAsync(int((nanos + 999_999'i64) div 1_000_000'i64))

proc retryAsync*[T](
    policy: BackoffPolicy;
    maxAttempts: int;
    sleep: AsyncSleepProc;
    operation: proc(): Future[T] {.closure.}
): Future[T] {.async.} =
  if maxAttempts < 1:
    raise newException(RetryConfigError, "maxAttempts must be at least 1")

  var attempt = 1
  while true:
    try:
      return await operation()
    except CatchableError:
      if attempt >= maxAttempts:
        raise
      await sleep(policy.delayFor(attempt))
      inc attempt

  raise newException(Defect, "unreachable async retry state")

proc retryAsync*[T](
    policy: BackoffPolicy;
    maxAttempts: int;
    operation: proc(): Future[T] {.closure.}
): Future[T] {.async.} =
  ## Retries an async operation using `sleepAsync` between attempts.
  await retryAsync(
    policy = policy,
    maxAttempts = maxAttempts,
    sleep = sleepDurationAsync,
    operation = operation
  )
