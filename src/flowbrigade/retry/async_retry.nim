import std/[asyncdispatch, times]

import ../backoff
import ../timeout
import ./errors
import ./sync

type
  AsyncSleepProc* = proc(delay: Duration): Future[void] {.closure.}

proc emit(observer: RetryObserverProc; event: RetryEvent) =
  if not observer.isNil:
    observer(event)

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
    operation: proc(): Future[T] {.closure.};
    observer: RetryObserverProc = nil;
    shouldRetry: RetryConditionProc = shouldRetryByDefault;
    deadline: Deadline = Deadline()
): Future[T] {.async.} =
  if maxAttempts < 1:
    raise newException(RetryConfigError, "maxAttempts must be at least 1")

  var attempt = 1
  while true:
    if deadline.isInitialized and deadline.expired:
      let error = newException(
        RetryDeadlineExceededError,
        "retry deadline expired before attempt " & $attempt
      )
      observer.emit(RetryEvent(kind: retryExhausted, attempt: attempt, error: error))
      raise error
    try:
      result = await operation()
      observer.emit(RetryEvent(kind: retrySucceeded, attempt: attempt))
      return result
    except CatchableError as exc:
      observer.emit(RetryEvent(kind: retryAttemptFailed, attempt: attempt, error: exc))
      if not shouldRetry(exc, attempt) or attempt >= maxAttempts:
        observer.emit(RetryEvent(kind: retryExhausted, attempt: attempt, error: exc))
        raise
      var delay = policy.delayFor(attempt)
      if deadline.isInitialized:
        delay = deadline.clamp(delay)
        if delay <= initDuration():
          let error = newException(RetryDeadlineExceededError, "retry deadline expired before waiting")
          observer.emit(RetryEvent(kind: retryExhausted, attempt: attempt, error: error))
          raise error
      observer.emit(RetryEvent(kind: retrySleeping, attempt: attempt, delay: delay, error: exc))
      await sleep(delay)
      inc attempt

  raise newException(Defect, "unreachable async retry state")

proc retryAsync*[T](
    policy: BackoffPolicy;
    maxAttempts: int;
    operation: proc(): Future[T] {.closure.};
    observer: RetryObserverProc = nil;
    shouldRetry: RetryConditionProc = shouldRetryByDefault;
    deadline: Deadline = Deadline()
): Future[T] {.async.} =
  ## Retries an async operation using `sleepAsync` between attempts.
  await retryAsync(
    policy = policy,
    maxAttempts = maxAttempts,
    sleep = sleepDurationAsync,
    operation = operation,
    observer = observer,
    shouldRetry = shouldRetry,
    deadline = deadline
  )
