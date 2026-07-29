import std/[os, times]

import ../backoff
import ./errors

type
  SleepProc* = proc(delay: Duration) {.closure.}
  RetryEventKind* = enum
    retryAttemptFailed, retrySleeping, retryExhausted, retrySucceeded

  RetryEvent* = object
    kind*: RetryEventKind
    attempt*: int
    delay*: Duration
    error*: ref CatchableError

  RetryObserverProc* = proc(event: RetryEvent) {.closure.}
  RetryConditionProc* = proc(error: ref CatchableError; attempt: int): bool {.closure.}

proc sleepDuration*(delay: Duration) =
  ## Sleeps for a Nim `Duration`, rounding sub-millisecond delays up.
  let nanos = delay.inNanoseconds
  if nanos <= 0:
    return
  sleep(int((nanos + 999_999'i64) div 1_000_000'i64))

proc emit(observer: RetryObserverProc; event: RetryEvent) =
  if not observer.isNil:
    observer(event)

proc shouldRetryByDefault*(error: ref CatchableError; attempt: int): bool =
  ## The default retries ordinary catchable failures but preserves cancellation.
  discard attempt
  not (error of RetryCancelledError)

proc retry*[T](
    policy: BackoffPolicy;
    maxAttempts: int;
    sleep: SleepProc;
    operation: proc(): T {.closure.};
    observer: RetryObserverProc = nil;
    shouldRetry: RetryConditionProc = shouldRetryByDefault
): T =
  if maxAttempts < 1:
    raise newException(RetryConfigError, "maxAttempts must be at least 1")

  var attempt = 1
  while true:
    try:
      result = operation()
      observer.emit(RetryEvent(kind: retrySucceeded, attempt: attempt))
      return result
    except CatchableError as exc:
      observer.emit(RetryEvent(kind: retryAttemptFailed, attempt: attempt, error: exc))
      if not shouldRetry(exc, attempt) or attempt >= maxAttempts:
        observer.emit(RetryEvent(kind: retryExhausted, attempt: attempt, error: exc))
        raise
      let delay = policy.delayFor(attempt)
      observer.emit(RetryEvent(kind: retrySleeping, attempt: attempt, delay: delay, error: exc))
      sleep(delay)
      inc attempt

  raise newException(Defect, "unreachable retry state")

proc retry*[T](
    policy: BackoffPolicy;
    maxAttempts: int;
    operation: proc(): T {.closure.};
    observer: RetryObserverProc = nil;
    shouldRetry: RetryConditionProc = shouldRetryByDefault
): T =
  ## Retries an operation using the default blocking sleep implementation.
  retry(
    policy = policy,
    maxAttempts = maxAttempts,
    sleep = sleepDuration,
    operation = operation,
    observer = observer,
    shouldRetry = shouldRetry
  )
