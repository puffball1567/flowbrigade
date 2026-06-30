import std/[math, times]

import ../internal/time_source
import ./errors
import ./result

type
  SlidingWindow* = object
    limit: int
    per: Duration
    previousUsed: int
    currentUsed: int
    windowStart: Duration
    timeSource: TimeSource

proc initSlidingWindow*(
    limit: int;
    per: Duration;
    timeSource: TimeSource
): SlidingWindow =
  if limit <= 0:
    raise newException(RateLimitConfigError, "limit must be positive")
  if per <= initDuration():
    raise newException(RateLimitConfigError, "per must be positive")
  SlidingWindow(
    limit: limit,
    per: per,
    windowStart: timeSource.now(),
    timeSource: timeSource
  )

proc initSlidingWindow*(limit: int; per: Duration): SlidingWindow =
  initSlidingWindow(limit = limit, per = per, timeSource = initTimeSource())

proc durationFromNanos(nanos: int64): Duration =
  initDuration(nanoseconds = nanos)

proc shiftWindows(limiter: var SlidingWindow) =
  let current = limiter.timeSource.now()
  let elapsed = current - limiter.windowStart
  if elapsed < limiter.per:
    return

  let windows = elapsed.inNanoseconds div limiter.per.inNanoseconds
  if windows == 1:
    limiter.previousUsed = limiter.currentUsed
  else:
    limiter.previousUsed = 0
  limiter.currentUsed = 0
  limiter.windowStart += durationFromNanos(windows * limiter.per.inNanoseconds)

proc validateCost(limiter: SlidingWindow; cost: int) =
  if cost <= 0:
    raise newException(RateLimitError, "cost must be positive")
  if cost > limiter.limit:
    raise newException(RateLimitError, "cost must not exceed window limit")

proc elapsedInWindow(limiter: SlidingWindow): Duration =
  max(initDuration(), limiter.timeSource.now() - limiter.windowStart)

proc weightedUsed(limiter: SlidingWindow): float =
  let elapsed = limiter.elapsedInWindow()
  let remainingFraction =
    1.0 - (float(elapsed.inNanoseconds) / float(limiter.per.inNanoseconds))
  float(limiter.currentUsed) + float(limiter.previousUsed) * max(0.0, remainingFraction)

proc resetAfter(limiter: SlidingWindow): Duration =
  let elapsed = limiter.elapsedInWindow()
  max(initDuration(), limiter.per - elapsed)

proc retryAfterFor(limiter: SlidingWindow; cost: int): Duration =
  let allowedAfterWeight = float(limiter.limit - limiter.currentUsed - cost)

  if limiter.previousUsed <= 0:
    return limiter.resetAfter()
  if allowedAfterWeight < 0.0:
    return limiter.resetAfter()

  let neededRemainingFraction = allowedAfterWeight / float(limiter.previousUsed)
  let elapsedNeeded =
    (1.0 - neededRemainingFraction) * float(limiter.per.inNanoseconds)
  let waitNanos = int64(ceil(elapsedNeeded - float(limiter.elapsedInWindow().inNanoseconds)))
  max(initDuration(), durationFromNanos(waitNanos))

proc resultFor(limiter: SlidingWindow; cost: int): RateLimitResult =
  let used = limiter.weightedUsed()
  let remaining = max(0, limiter.limit - int(ceil(used)))
  let reset = limiter.resetAfter()
  if used + float(cost) <= float(limiter.limit):
    return allowedResult(
      limit = limiter.limit,
      remaining = max(0, limiter.limit - int(ceil(used + float(cost)))),
      resetAfter = reset
    )

  deniedResult(
    limit = limiter.limit,
    remaining = remaining,
    retryAfter = limiter.retryAfterFor(cost),
    resetAfter = reset
  )

proc inspect*(limiter: var SlidingWindow; cost = 1): RateLimitResult =
  limiter.validateCost(cost)
  limiter.shiftWindows()
  limiter.resultFor(cost)

proc consume*(limiter: var SlidingWindow; cost = 1): RateLimitResult =
  let checked = limiter.inspect(cost)
  if checked.allowed:
    limiter.currentUsed += cost
  checked

proc allow*(limiter: var SlidingWindow; cost = 1): bool =
  limiter.consume(cost).allowed

proc reset*(limiter: var SlidingWindow) =
  ## Clears weighted usage and starts a fresh local window.
  limiter.previousUsed = 0
  limiter.currentUsed = 0
  limiter.windowStart = limiter.timeSource.now()

proc configuredLimit*(limiter: SlidingWindow): int =
  limiter.limit

proc configuredPeriod*(limiter: SlidingWindow): Duration =
  limiter.per

proc currentWindowUse*(limiter: var SlidingWindow): int =
  limiter.shiftWindows()
  limiter.currentUsed
