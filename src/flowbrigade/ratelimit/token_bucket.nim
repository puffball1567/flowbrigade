import std/[math, times]

import ../internal/time_source
import ./errors
import ./result

type
  TokenBucket* = object
    rate: int
    per: Duration
    burst: int
    tokens: float
    lastRefill: Duration
    timeSource: TimeSource

proc initTokenBucket*(
    rate: int;
    per: Duration;
    burst: int;
    timeSource: TimeSource
): TokenBucket =
  if rate <= 0:
    raise newException(RateLimitConfigError, "rate must be positive")
  if per <= initDuration():
    raise newException(RateLimitConfigError, "per must be positive")
  if burst <= 0:
    raise newException(RateLimitConfigError, "burst must be positive")
  TokenBucket(
    rate: rate,
    per: per,
    burst: burst,
    tokens: float(burst),
    lastRefill: timeSource.now(),
    timeSource: timeSource
  )

proc initTokenBucket*(rate: int; per: Duration; burst: int): TokenBucket =
  initTokenBucket(rate = rate, per = per, burst = burst, timeSource = initTimeSource())

proc refill(limiter: var TokenBucket) =
  let current = limiter.timeSource.now()
  let elapsed = current - limiter.lastRefill
  if elapsed <= initDuration():
    return

  let gained = float(elapsed.inNanoseconds) *
    float(limiter.rate) / float(limiter.per.inNanoseconds)
  limiter.tokens = min(float(limiter.burst), limiter.tokens + gained)
  limiter.lastRefill = current

proc validateCost(limiter: TokenBucket; cost: int) =
  if cost <= 0:
    raise newException(RateLimitError, "cost must be positive")
  if cost > limiter.burst:
    raise newException(RateLimitError, "cost must not exceed burst capacity")

proc durationFromNanos(nanos: int64): Duration =
  initDuration(nanoseconds = nanos)

proc ceilDurationNanos(value: float): Duration =
  if value <= 0.0:
    return initDuration()
  durationFromNanos(int64(ceil(value)))

proc timeForTokens(limiter: TokenBucket; tokens: float): Duration =
  ceilDurationNanos(tokens * float(limiter.per.inNanoseconds) / float(limiter.rate))

proc resultFor(limiter: TokenBucket; cost: int): RateLimitResult =
  let remaining = int(floor(limiter.tokens))
  let resetAfter = limiter.timeForTokens(float(limiter.burst) - limiter.tokens)
  if limiter.tokens >= float(cost):
    return allowedResult(
      limit = limiter.burst,
      remaining = int(floor(limiter.tokens - float(cost))),
      resetAfter = resetAfter
    )

  let missing = float(cost) - limiter.tokens
  deniedResult(
    limit = limiter.burst,
    remaining = remaining,
    retryAfter = limiter.timeForTokens(missing),
    resetAfter = resetAfter
  )

proc inspect*(limiter: var TokenBucket; cost = 1): RateLimitResult =
  limiter.validateCost(cost)
  limiter.refill()
  limiter.resultFor(cost)

proc consume*(limiter: var TokenBucket; cost = 1): RateLimitResult =
  let checked = limiter.inspect(cost)
  if checked.allowed:
    limiter.tokens -= float(cost)
  checked

proc allow*(limiter: var TokenBucket; cost = 1): bool =
  limiter.consume(cost).allowed
