import std/[times]

import flowbrigade

type ApiError = object of CatchableError

var attempts = 0
var observed: seq[RetryEventKind] = @[]

let policy = expBackoff(
  initial = 50.ms,
  factor = 2.0,
  maxDelay = 1.sec,
  jitter = noJitter
)

proc callApi(): string =
  inc attempts
  if attempts < 3:
    raise newException(ApiError, "temporary upstream failure")
  "ok"

let result = retry(
  policy = policy,
  maxAttempts = 3,
  sleep = proc(delay: Duration) =
    discard,
  operation = callApi,
  observer = proc(event: RetryEvent) =
    observed.add(event.kind)
)

doAssert result == "ok"
doAssert observed == @[retryAttemptFailed, retrySleeping, retryAttemptFailed, retrySleeping, retrySucceeded]
