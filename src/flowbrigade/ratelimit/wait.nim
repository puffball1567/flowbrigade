import std/[asyncdispatch, times]

import ./result

type
  ## Blocking or test-injected sleep callback for rate-limit waits.
  RateLimitSleepProc* = proc(delay: Duration) {.closure.}
  ## Async sleep callback for rate-limit waits.
  AsyncRateLimitSleepProc* = proc(delay: Duration): Future[void] {.closure.}

proc waitDelay*(decision: RateLimitResult): Duration =
  ## Returns zero for allowed decisions, otherwise the decision retry delay.
  if decision.allowed:
    initDuration()
  else:
    decision.retryAfter

proc wait*(decision: RateLimitResult; sleep: RateLimitSleepProc) =
  ## Sleeps until retry is allowed when the decision was denied.
  ##
  ## The sleep proc is injected so applications can use `sleep`, framework
  ## schedulers, or tests without coupling this module to a runtime.
  if sleep.isNil:
    raise newException(ValueError, "sleep proc must not be nil")
  let delay = decision.waitDelay()
  if delay > initDuration():
    sleep(delay)

proc waitAsync*(decision: RateLimitResult; sleep: AsyncRateLimitSleepProc): Future[void] {.async.} =
  ## Async version of `wait`.
  if sleep.isNil:
    raise newException(ValueError, "sleep proc must not be nil")
  let delay = decision.waitDelay()
  if delay > initDuration():
    await sleep(delay)
