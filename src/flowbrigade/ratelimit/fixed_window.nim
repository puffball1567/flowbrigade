import std/times

import ../internal/time_source
import ./errors
import ./result

type
  FixedWindow* = object
    limit: int
    per: Duration
    used: int
    windowStart: Duration
    timeSource: TimeSource

proc initFixedWindow*(
    limit: int;
    per: Duration;
    timeSource: TimeSource
): FixedWindow =
  if limit <= 0:
    raise newException(RateLimitConfigError, "limit must be positive")
  if per <= initDuration():
    raise newException(RateLimitConfigError, "per must be positive")
  FixedWindow(
    limit: limit,
    per: per,
    windowStart: timeSource.now(),
    timeSource: timeSource
  )

proc initFixedWindow*(limit: int; per: Duration): FixedWindow =
  initFixedWindow(limit = limit, per = per, timeSource = initTimeSource())

proc resetIfNeeded(limiter: var FixedWindow) =
  let current = limiter.timeSource.now()
  if current - limiter.windowStart >= limiter.per:
    limiter.windowStart = current
    limiter.used = 0

proc validateCost(limiter: FixedWindow; cost: int) =
  if cost <= 0:
    raise newException(RateLimitError, "cost must be positive")
  if cost > limiter.limit:
    raise newException(RateLimitError, "cost must not exceed window limit")

proc windowRemaining(limiter: FixedWindow): Duration =
  let elapsed = limiter.timeSource.now() - limiter.windowStart
  max(initDuration(), limiter.per - elapsed)

proc resultFor(limiter: FixedWindow; cost: int): RateLimitResult =
  let remaining = limiter.limit - limiter.used
  let resetAfter = limiter.windowRemaining()
  if limiter.used + cost <= limiter.limit:
    return allowedResult(
      limit = limiter.limit,
      remaining = remaining - cost,
      resetAfter = resetAfter
    )

  deniedResult(
    limit = limiter.limit,
    remaining = remaining,
    retryAfter = resetAfter,
    resetAfter = resetAfter
  )

proc inspect*(limiter: var FixedWindow; cost = 1): RateLimitResult =
  limiter.validateCost(cost)
  limiter.resetIfNeeded()
  limiter.resultFor(cost)

proc consume*(limiter: var FixedWindow; cost = 1): RateLimitResult =
  let checked = limiter.inspect(cost)
  if checked.allowed:
    limiter.used += cost
  checked

proc allow*(limiter: var FixedWindow; cost = 1): bool =
  limiter.consume(cost).allowed

proc reset*(limiter: var FixedWindow) =
  ## Clears the current window usage and starts a fresh local window.
  limiter.used = 0
  limiter.windowStart = limiter.timeSource.now()

proc configuredLimit*(limiter: FixedWindow): int =
  limiter.limit

proc configuredPeriod*(limiter: FixedWindow): Duration =
  limiter.per

proc inUse*(limiter: var FixedWindow): int =
  limiter.resetIfNeeded()
  limiter.used
