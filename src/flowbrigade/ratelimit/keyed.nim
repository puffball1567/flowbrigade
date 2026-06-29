import std/[tables, times]

import ../internal/time_source
import ./errors
import ./result

const DefaultMaxKeys* = 65_536

type
  KeyState = object
    used: int
    windowStart: Duration

  KeyedFixedWindow*[K] = object
    limit: int
    per: Duration
    maxKeys: int
    entries: Table[K, KeyState]
    timeSource: TimeSource

proc initKeyedFixedWindow*[K](
    limit: int;
    per: Duration;
    timeSource: TimeSource;
    maxKeys = DefaultMaxKeys
): KeyedFixedWindow[K] =
  if limit <= 0:
    raise newException(RateLimitConfigError, "limit must be positive")
  if per <= initDuration():
    raise newException(RateLimitConfigError, "per must be positive")
  if maxKeys <= 0:
    raise newException(RateLimitConfigError, "maxKeys must be positive")
  KeyedFixedWindow[K](
    limit: limit,
    per: per,
    maxKeys: maxKeys,
    entries: initTable[K, KeyState](),
    timeSource: timeSource
  )

proc initKeyedFixedWindow*[K](
    limit: int;
    per: Duration;
    maxKeys = DefaultMaxKeys
): KeyedFixedWindow[K] =
  initKeyedFixedWindow[K](
    limit = limit,
    per = per,
    timeSource = initTimeSource(),
    maxKeys = maxKeys
  )

proc pruneExpired[K](limiter: var KeyedFixedWindow[K]; current: Duration) =
  var expired: seq[K] = @[]
  for key, state in limiter.entries.pairs:
    if current - state.windowStart >= limiter.per:
      expired.add(key)
  for key in expired:
    limiter.entries.del(key)

proc validateCost[K](limiter: KeyedFixedWindow[K]; cost: int) =
  if cost <= 0:
    raise newException(RateLimitError, "cost must be positive")
  if cost > limiter.limit:
    raise newException(RateLimitError, "cost must not exceed window limit")

proc ensureKeyCapacity[K](limiter: var KeyedFixedWindow[K]; key: K; current: Duration) =
  let isNewKey = not limiter.entries.hasKey(key)
  if isNewKey and limiter.entries.len >= limiter.maxKeys:
    limiter.pruneExpired(current)
    if limiter.entries.len >= limiter.maxKeys:
      raise newException(RateLimitError, "key capacity exceeded")

proc currentState[K](
    limiter: KeyedFixedWindow[K];
    key: K;
    current: Duration
): KeyState =
  result = limiter.entries.getOrDefault(key, KeyState(windowStart: current))
  if current - result.windowStart >= limiter.per:
    result.windowStart = current
    result.used = 0

proc resultFor[K](
    limiter: KeyedFixedWindow[K];
    state: KeyState;
    cost: int;
    current: Duration
): RateLimitResult =
  let remaining = limiter.limit - state.used
  let resetAfter = max(initDuration(), limiter.per - (current - state.windowStart))
  if state.used + cost <= limiter.limit:
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

proc inspect*[K](
    limiter: var KeyedFixedWindow[K];
    key: K;
    cost = 1
): RateLimitResult =
  limiter.validateCost(cost)
  let current = limiter.timeSource.now()
  limiter.ensureKeyCapacity(key, current)
  let state = limiter.currentState(key, current)
  limiter.resultFor(state, cost, current)

proc consume*[K](
    limiter: var KeyedFixedWindow[K];
    key: K;
    cost = 1
): RateLimitResult =
  let checked = limiter.inspect(key, cost)
  let current = limiter.timeSource.now()
  var state = limiter.currentState(key, current)
  if state.used + cost <= limiter.limit:
    state.used += cost
    limiter.entries[key] = state
  else:
    limiter.entries[key] = state
  checked

proc allow*[K](limiter: var KeyedFixedWindow[K]; key: K; cost = 1): bool =
  limiter.consume(key, cost).allowed
