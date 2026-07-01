import std/[strutils, tables, times]

import ../internal/time_source
import ./errors
import ./result

const DefaultGcraMaxKeys* = 65_536

type
  GcraLimiter* = object
    rate: int
    per: Duration
    burst: int
    interval: Duration
    tat: Duration
    timeSource: TimeSource

  GcraKeyState = object
    tat: Duration

  KeyedGcraLimiter*[K] = object
    rate: int
    per: Duration
    burst: int
    interval: Duration
    maxKeys: int
    entries: Table[K, GcraKeyState]
    timeSource: TimeSource

proc ceilDiv(a, b: int64): int64 =
  if b <= 0:
    raise newException(RateLimitConfigError, "divisor must be positive")
  if a <= 0:
    0
  else:
    ((a - 1) div b) + 1

proc durationFromNanos(nanos: int64): Duration =
  initDuration(nanoseconds = nanos)

proc intervalFor(rate: int; per: Duration): Duration =
  if rate <= 0:
    raise newException(RateLimitConfigError, "rate must be positive")
  if per <= initDuration():
    raise newException(RateLimitConfigError, "per must be positive")
  let nanos = per.inNanoseconds
  if nanos <= 0:
    raise newException(RateLimitConfigError, "per must be positive")
  durationFromNanos(max(1'i64, ceilDiv(nanos, rate.int64)))

proc validateConfig(rate: int; per: Duration; burst: int) =
  discard intervalFor(rate, per)
  if burst <= 0:
    raise newException(RateLimitConfigError, "burst must be positive")

proc validateCost(burst, cost: int) =
  if cost <= 0:
    raise newException(RateLimitError, "cost must be positive")
  if cost > burst:
    raise newException(RateLimitError, "cost must not exceed burst capacity")

proc validateKey(key: string) =
  if key.len == 0:
    raise newException(RateLimitError, "key must not be empty")
  if key.strip().len == 0:
    raise newException(RateLimitError, "key must not be blank")
  for ch in key:
    if ord(ch) < 32 or ord(ch) == 127:
      raise newException(RateLimitError, "key must not contain control characters")

proc validateKey[K](key: K) =
  when K is string:
    validateKey(key)

proc mulDuration(duration: Duration; factor: int): Duration =
  if factor <= 0:
    return initDuration()
  durationFromNanos(duration.inNanoseconds * factor.int64)

proc ceilUnits(duration, unit: Duration): int =
  int(ceilDiv(duration.inNanoseconds, unit.inNanoseconds))

proc currentAvailable(tat, now, interval: Duration; burst: int): int =
  if tat <= now:
    return burst
  max(0, burst - ceilUnits(tat - now, interval))

proc decision(
    burst: int;
    interval: Duration;
    tat: Duration;
    now: Duration;
    cost: int
): tuple[result: RateLimitResult; nextTat: Duration] =
  validateCost(burst, cost)

  let costTime = interval.mulDuration(cost)
  let burstTime = interval.mulDuration(burst)
  let earliest = max(initDuration(), tat + costTime - burstTime)
  let resetAfter = max(initDuration(), tat - now)

  if now >= earliest:
    let nextTat = max(now, tat) + costTime
    let remaining = currentAvailable(nextTat, now, interval, burst)
    return (
      result: allowedResult(
        limit = burst,
        remaining = remaining,
        resetAfter = max(initDuration(), nextTat - now)
      ),
      nextTat: nextTat
    )

  (
    result: deniedResult(
      limit = burst,
      remaining = currentAvailable(tat, now, interval, burst),
      retryAfter = earliest - now,
      resetAfter = resetAfter
    ),
    nextTat: tat
  )

proc initGcraLimiter*(
    rate: int;
    per: Duration;
    burst: int;
    timeSource: TimeSource
): GcraLimiter =
  ## Creates an in-process GCRA-style limiter.
  ##
  ## GCRA is a public, standards-described traffic policing approach based on
  ## theoretical arrival time. This implementation is written against that
  ## algorithmic description and FlowBrigade's result API.
  if timeSource.isNil:
    raise newException(RateLimitConfigError, "timeSource must not be nil")
  validateConfig(rate, per, burst)
  GcraLimiter(
    rate: rate,
    per: per,
    burst: burst,
    interval: intervalFor(rate, per),
    tat: timeSource.now(),
    timeSource: timeSource
  )

proc initGcraLimiter*(rate: int; per: Duration; burst: int): GcraLimiter =
  initGcraLimiter(rate = rate, per = per, burst = burst, timeSource = initTimeSource())

proc inspect*(limiter: GcraLimiter; cost = 1): RateLimitResult =
  decision(
    limiter.burst,
    limiter.interval,
    limiter.tat,
    limiter.timeSource.now(),
    cost
  ).result

proc consume*(limiter: var GcraLimiter; cost = 1): RateLimitResult =
  let checked = decision(
    limiter.burst,
    limiter.interval,
    limiter.tat,
    limiter.timeSource.now(),
    cost
  )
  if checked.result.allowed:
    limiter.tat = checked.nextTat
  checked.result

proc allow*(limiter: var GcraLimiter; cost = 1): bool =
  limiter.consume(cost).allowed

proc reset*(limiter: var GcraLimiter) =
  limiter.tat = limiter.timeSource.now()

proc configuredRate*(limiter: GcraLimiter): int =
  limiter.rate

proc configuredPeriod*(limiter: GcraLimiter): Duration =
  limiter.per

proc configuredBurst*(limiter: GcraLimiter): int =
  limiter.burst

proc configuredInterval*(limiter: GcraLimiter): Duration =
  limiter.interval

proc availableCapacity*(limiter: GcraLimiter): int =
  currentAvailable(limiter.tat, limiter.timeSource.now(), limiter.interval, limiter.burst)

proc initKeyedGcraLimiter*[K](
    rate: int;
    per: Duration;
    burst: int;
    timeSource: TimeSource;
    maxKeys = DefaultGcraMaxKeys
): KeyedGcraLimiter[K] =
  if timeSource.isNil:
    raise newException(RateLimitConfigError, "timeSource must not be nil")
  validateConfig(rate, per, burst)
  if maxKeys <= 0:
    raise newException(RateLimitConfigError, "maxKeys must be positive")
  KeyedGcraLimiter[K](
    rate: rate,
    per: per,
    burst: burst,
    interval: intervalFor(rate, per),
    maxKeys: maxKeys,
    entries: initTable[K, GcraKeyState](),
    timeSource: timeSource
  )

proc initKeyedGcraLimiter*[K](
    rate: int;
    per: Duration;
    burst: int;
    maxKeys = DefaultGcraMaxKeys
): KeyedGcraLimiter[K] =
  initKeyedGcraLimiter[K](
    rate = rate,
    per = per,
    burst = burst,
    timeSource = initTimeSource(),
    maxKeys = maxKeys
  )

proc pruneIdle[K](limiter: var KeyedGcraLimiter[K]; now: Duration) =
  var idle: seq[K] = @[]
  for key, state in limiter.entries.pairs:
    if state.tat <= now:
      idle.add(key)
  for key in idle:
    limiter.entries.del(key)

proc ensureKeyCapacity[K](limiter: var KeyedGcraLimiter[K]; key: K; now: Duration) =
  let isNewKey = not limiter.entries.hasKey(key)
  if isNewKey and limiter.entries.len >= limiter.maxKeys:
    limiter.pruneIdle(now)
    if limiter.entries.len >= limiter.maxKeys:
      raise newException(RateLimitError, "key capacity exceeded")

proc stateFor[K](limiter: KeyedGcraLimiter[K]; key: K; now: Duration): GcraKeyState =
  limiter.entries.getOrDefault(key, GcraKeyState(tat: now))

proc inspect*[K](limiter: var KeyedGcraLimiter[K]; key: K; cost = 1): RateLimitResult =
  validateKey(key)
  let now = limiter.timeSource.now()
  limiter.ensureKeyCapacity(key, now)
  let state = limiter.stateFor(key, now)
  decision(
    limiter.burst,
    limiter.interval,
    state.tat,
    now,
    cost
  ).result

proc consume*[K](limiter: var KeyedGcraLimiter[K]; key: K; cost = 1): RateLimitResult =
  validateKey(key)
  let now = limiter.timeSource.now()
  limiter.ensureKeyCapacity(key, now)
  let state = limiter.stateFor(key, now)
  let checked = decision(
    limiter.burst,
    limiter.interval,
    state.tat,
    now,
    cost
  )
  if checked.result.allowed:
    limiter.entries[key] = GcraKeyState(tat: checked.nextTat)
  elif limiter.entries.hasKey(key):
    limiter.entries[key] = state
  checked.result

proc allow*[K](limiter: var KeyedGcraLimiter[K]; key: K; cost = 1): bool =
  limiter.consume(key, cost).allowed

proc pruneIdle*[K](limiter: var KeyedGcraLimiter[K]) =
  ## Removes keys whose theoretical arrival time has fully caught up.
  limiter.pruneIdle(limiter.timeSource.now())

proc activeKeys*[K](limiter: var KeyedGcraLimiter[K]): int =
  limiter.pruneIdle()
  limiter.entries.len

proc clear*[K](limiter: var KeyedGcraLimiter[K]; key: K): bool =
  validateKey(key)
  result = limiter.entries.hasKey(key)
  limiter.entries.del(key)

proc reset*[K](limiter: var KeyedGcraLimiter[K]; key: K): bool =
  limiter.clear(key)

proc resetAll*[K](limiter: var KeyedGcraLimiter[K]): int =
  result = limiter.entries.len
  limiter.entries.clear()

proc configuredRate*[K](limiter: KeyedGcraLimiter[K]): int =
  limiter.rate

proc configuredPeriod*[K](limiter: KeyedGcraLimiter[K]): Duration =
  limiter.per

proc configuredBurst*[K](limiter: KeyedGcraLimiter[K]): int =
  limiter.burst

proc configuredInterval*[K](limiter: KeyedGcraLimiter[K]): Duration =
  limiter.interval

proc keyCapacity*[K](limiter: KeyedGcraLimiter[K]): int =
  limiter.maxKeys
