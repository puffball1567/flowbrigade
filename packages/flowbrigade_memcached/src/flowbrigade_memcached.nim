import std/[parseutils, strutils, times]

import flowbrigade/ratelimit

const DefaultMaxCasRetries* = 8
const MaxMemcachedKeyLength* = 250

type
  MemcachedGetResult* = object
    found*: bool
    value*: string
    cas*: string

  MemcachedGetsProc* = proc(key: string): MemcachedGetResult {.closure.}
  MemcachedAddProc* = proc(key, value: string; ttl: Duration): bool {.closure.}
  MemcachedCasProc* = proc(key, value, cas: string; ttl: Duration): bool {.closure.}
  MemcachedDeleteProc* = proc(key: string): bool {.closure.}

  MemcachedRateLimitStorage* = ref object
    gets: MemcachedGetsProc
    add: MemcachedAddProc
    cas: MemcachedCasProc
    delete: MemcachedDeleteProc
    keyPrefix: string
    maxCasRetries: int

  WindowState = object
    used: int
    windowStart: Duration

proc memcachedRateLimitCapabilities*(): RateLimitCapabilities =
  ## Describes guarantees expected from the Memcached CAS adapter.
  ##
  ## This assumes the chosen client provides real `gets`/`cas` semantics.
  ## Strict future-capacity reservation is not implemented.
  initRateLimitCapabilities([
    rlcInspect,
    rlcAtomicConsume,
    rlcClear,
    rlcTtl,
    rlcDistributed
  ])

proc hasControlOrWhitespace(value: string): bool =
  for ch in value:
    if ord(ch) <= 32 or ord(ch) == 127:
      return true
  false

proc validateMemcachedKeyPart(name, value: string) =
  if value.strip().len == 0:
    raise newException(RateLimitConfigError, name & " must not be blank")
  if value.hasControlOrWhitespace():
    raise newException(RateLimitConfigError, name & " must not contain whitespace or control characters")

proc validateStorage(storage: MemcachedRateLimitStorage) =
  if storage.isNil:
    raise newException(RateLimitConfigError, "storage must not be nil")
  if storage.gets.isNil:
    raise newException(RateLimitConfigError, "gets proc must not be nil")
  if storage.add.isNil:
    raise newException(RateLimitConfigError, "add proc must not be nil")
  if storage.cas.isNil:
    raise newException(RateLimitConfigError, "cas proc must not be nil")
  if storage.delete.isNil:
    raise newException(RateLimitConfigError, "delete proc must not be nil")
  if storage.maxCasRetries <= 0:
    raise newException(RateLimitConfigError, "maxCasRetries must be positive")

proc validateLimit(limit: int; per: Duration) =
  if limit <= 0:
    raise newException(RateLimitConfigError, "limit must be positive")
  if per <= initDuration():
    raise newException(RateLimitConfigError, "per must be positive")

proc validateCost(limit, cost: int) =
  if cost <= 0:
    raise newException(RateLimitError, "cost must be positive")
  if cost > limit:
    raise newException(RateLimitError, "cost must not exceed window limit")

proc durationFromMillis(value: int64): Duration =
  initDuration(milliseconds = int(value))

proc millis(value: Duration): int64 =
  value.inMilliseconds

proc memcachedKey(storage: MemcachedRateLimitStorage; key: string): string =
  result = storage.keyPrefix & ":fixed:" & key
  if result.len > MaxMemcachedKeyLength:
    raise newException(RateLimitError, "Memcached key is too long")
  if result.hasControlOrWhitespace():
    raise newException(RateLimitError, "Memcached key must not contain whitespace or control characters")

proc encodeState(state: WindowState): string =
  $state.used & ":" & $state.windowStart.millis()

proc parseState(value: string): WindowState =
  let parts = value.split(":")
  if parts.len != 2:
    raise newException(RateLimitError, "Memcached rate limit value is malformed")

  var used = 0
  var windowStartMs = 0
  if parseInt(parts[0], used) != parts[0].len:
    raise newException(RateLimitError, "Memcached rate limit count is malformed")
  if parseInt(parts[1], windowStartMs) != parts[1].len:
    raise newException(RateLimitError, "Memcached rate limit window is malformed")
  if used < 0:
    raise newException(RateLimitError, "Memcached rate limit count is negative")

  WindowState(
    used: used,
    windowStart: durationFromMillis(windowStartMs.int64)
  )

proc resultFor(
    limit: int;
    per: Duration;
    state: WindowState;
    cost: int;
    current: Duration
): RateLimitResult =
  let elapsed = current - state.windowStart
  let resetAfter = max(initDuration(), per - elapsed)
  let remaining = limit - state.used
  if state.used + cost <= limit:
    return allowedResult(
      limit = limit,
      remaining = remaining - cost,
      resetAfter = resetAfter
    )

  deniedResult(
    limit = limit,
    remaining = max(0, remaining),
    retryAfter = resetAfter,
    resetAfter = resetAfter
  )

proc stateFromGet(
    value: MemcachedGetResult;
    current: Duration
): WindowState =
  if value.found:
    parseState(value.value)
  else:
    WindowState(used: 0, windowStart: current)

proc inspectFixedWindow(
    storage: MemcachedRateLimitStorage;
    key: string;
    limit: int;
    per: Duration;
    cost: int;
    current: Duration
): RateLimitResult =
  validateLimit(limit, per)
  validateCost(limit, cost)
  let fullKey = storage.memcachedKey(key)
  let state = storage.gets(fullKey).stateFromGet(current)
  resultFor(limit, per, state, cost, current)

proc consumeFixedWindow(
    storage: MemcachedRateLimitStorage;
    key: string;
    limit: int;
    per: Duration;
    cost: int;
    current: Duration
): RateLimitResult =
  validateLimit(limit, per)
  validateCost(limit, cost)
  let fullKey = storage.memcachedKey(key)

  for _ in 0 ..< storage.maxCasRetries:
    let currentValue = storage.gets(fullKey)
    let state = currentValue.stateFromGet(current)
    let checked = resultFor(limit, per, state, cost, current)
    if not checked.allowed:
      return checked

    let nextState = WindowState(used: state.used + cost, windowStart: state.windowStart)
    if currentValue.found:
      if storage.cas(fullKey, nextState.encodeState(), currentValue.cas, per):
        return checked
    else:
      if storage.add(fullKey, nextState.encodeState(), per):
        return checked

  raise newException(RateLimitError, "Memcached rate limit CAS retry limit exceeded")

proc clearFixedWindow(storage: MemcachedRateLimitStorage; key: string): bool =
  storage.delete(storage.memcachedKey(key))

proc initMemcachedRateLimitStorage*(
    gets: MemcachedGetsProc;
    add: MemcachedAddProc;
    cas: MemcachedCasProc;
    delete: MemcachedDeleteProc;
    keyPrefix = "flowbrigade";
    maxCasRetries = DefaultMaxCasRetries
): MemcachedRateLimitStorage =
  ## Creates a Memcached-backed storage adapter for stored fixed-window limits.
  ##
  ## The adapter expects `gets` and `cas` semantics from the client. Consume
  ## operations retry CAS conflicts up to `maxCasRetries`.
  validateMemcachedKeyPart("keyPrefix", keyPrefix)
  result = MemcachedRateLimitStorage(
    gets: gets,
    add: add,
    cas: cas,
    delete: delete,
    keyPrefix: keyPrefix,
    maxCasRetries: maxCasRetries
  )
  result.validateStorage()

proc asRateLimitStorage*(storage: MemcachedRateLimitStorage): RateLimitStorage =
  ## Converts Memcached callbacks into FlowBrigade's sync storage adapter.
  storage.validateStorage()
  RateLimitStorage(
    inspectFixedWindow: proc(
      key: string;
      limit: int;
      per: Duration;
      cost: int;
      current: Duration
    ): RateLimitResult =
      storage.inspectFixedWindow(key, limit, per, cost, current),
    consumeFixedWindow: proc(
      key: string;
      limit: int;
      per: Duration;
      cost: int;
      current: Duration
    ): RateLimitResult =
      storage.consumeFixedWindow(key, limit, per, cost, current),
    clearFixedWindow: proc(key: string): bool =
      storage.clearFixedWindow(key)
  )
