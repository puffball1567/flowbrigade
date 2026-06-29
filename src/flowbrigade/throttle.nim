import std/times

import ./internal/time_source

type
  ThrottleConfigError* = object of ValueError

  Throttle* = object
    every: Duration
    hasLastAllowed: bool
    lastAllowed: Duration
    timeSource: TimeSource

proc initThrottle*(every: Duration; timeSource: TimeSource): Throttle =
  if every <= initDuration():
    raise newException(ThrottleConfigError, "throttle interval must be positive")
  Throttle(every: every, timeSource: timeSource)

proc initThrottle*(every: Duration): Throttle =
  initThrottle(every = every, timeSource = initTimeSource())

proc allow*(throttle: var Throttle): bool =
  let current = throttle.timeSource.now()
  if not throttle.hasLastAllowed:
    throttle.hasLastAllowed = true
    throttle.lastAllowed = current
    return true
  if current - throttle.lastAllowed >= throttle.every:
    throttle.lastAllowed = current
    return true
  false

proc reset*(throttle: var Throttle) =
  throttle.hasLastAllowed = false
  throttle.lastAllowed = initDuration()
