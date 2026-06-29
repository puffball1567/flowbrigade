import std/[asyncdispatch, strutils, times]

import ../internal/time_source
import ./errors
import ./result
import ./storage

type
  ## Async storage callback used by stored fixed-window limiters.
  AsyncFixedWindowStorageProc* = proc(
    key: string;
    limit: int;
    per: Duration;
    cost: int;
    current: Duration
  ): Future[RateLimitResult] {.closure.}

  ## Async clear callback for stored fixed-window limiters.
  AsyncClearFixedWindowStorageProc* = proc(key: string): Future[bool] {.closure.}

  ## Async callback bundle for fixed-window storage adapters.
  AsyncRateLimitStorage* = object
    inspectFixedWindow*: AsyncFixedWindowStorageProc
    consumeFixedWindow*: AsyncFixedWindowStorageProc
    clearFixedWindow*: AsyncClearFixedWindowStorageProc

  ## Async fixed-window limiter backed by an async storage adapter.
  AsyncStoredFixedWindow* = object
    prefix: string
    limit: int
    per: Duration
    maxKeyLength: int
    storage: AsyncRateLimitStorage
    timeSource: TimeSource
    audit: StoredFixedWindowAuditProc

proc validateAsyncStorageProc(storage: AsyncRateLimitStorage) =
  if storage.inspectFixedWindow.isNil:
    raise newException(RateLimitConfigError, "inspectFixedWindow proc must not be nil")
  if storage.consumeFixedWindow.isNil:
    raise newException(RateLimitConfigError, "consumeFixedWindow proc must not be nil")
  if storage.clearFixedWindow.isNil:
    raise newException(RateLimitConfigError, "clearFixedWindow proc must not be nil")

proc validateFixedWindowConfig(limit: int; per: Duration) =
  if limit <= 0:
    raise newException(RateLimitConfigError, "limit must be positive")
  if per <= initDuration():
    raise newException(RateLimitConfigError, "per must be positive")

proc hasControlChar(value: string): bool =
  for ch in value:
    if ord(ch) < 32 or ord(ch) == 127:
      return true
  false

proc validatePrefix(prefix: string; maxKeyLength: int) =
  if maxKeyLength <= 0:
    raise newException(RateLimitConfigError, "maxKeyLength must be positive")
  if prefix.len == 0 or prefix.strip().len == 0:
    raise newException(RateLimitConfigError, "prefix must not be blank")
  if prefix.len > maxKeyLength:
    raise newException(RateLimitConfigError, "prefix is too long")
  if prefix.hasControlChar():
    raise newException(RateLimitConfigError, "prefix must not contain control characters")

proc validateKeyPart(name, value: string; maxLength: int) =
  if value.len == 0:
    raise newException(RateLimitError, name & " must not be empty")
  if value.len > maxLength:
    raise newException(RateLimitError, name & " is too long")
  if value.strip().len == 0:
    raise newException(RateLimitError, name & " must not be blank")
  if value.hasControlChar():
    raise newException(RateLimitError, name & " must not contain control characters")

proc validateCost(limit, cost: int) =
  if cost <= 0:
    raise newException(RateLimitError, "cost must be positive")
  if cost > limit:
    raise newException(RateLimitError, "cost must not exceed window limit")

proc storageKey(limiter: AsyncStoredFixedWindow; key: string): string =
  validateKeyPart("key", key, limiter.maxKeyLength)
  limiter.prefix & ":" & key

proc asAsyncRateLimitStorage*(storage: RateLimitStorage): AsyncRateLimitStorage =
  ## Wraps a synchronous storage adapter for use with async stored limiters.
  ##
  ## This is a compatibility helper. It does not make blocking storage I/O
  ## non-blocking; true async clients should implement `AsyncRateLimitStorage`
  ## directly.
  if storage.inspectFixedWindow.isNil:
    raise newException(RateLimitConfigError, "inspectFixedWindow proc must not be nil")
  if storage.consumeFixedWindow.isNil:
    raise newException(RateLimitConfigError, "consumeFixedWindow proc must not be nil")
  if storage.clearFixedWindow.isNil:
    raise newException(RateLimitConfigError, "clearFixedWindow proc must not be nil")

  AsyncRateLimitStorage(
    inspectFixedWindow: proc(
      key: string;
      limit: int;
      per: Duration;
      cost: int;
      current: Duration
    ): Future[RateLimitResult] {.async.} =
      storage.inspectFixedWindow(key, limit, per, cost, current),
    consumeFixedWindow: proc(
      key: string;
      limit: int;
      per: Duration;
      cost: int;
      current: Duration
    ): Future[RateLimitResult] {.async.} =
      storage.consumeFixedWindow(key, limit, per, cost, current),
    clearFixedWindow: proc(key: string): Future[bool] {.async.} =
      storage.clearFixedWindow(key)
  )

proc initAsyncStoredFixedWindow*(
    prefix: string;
    limit: int;
    per: Duration;
    storage: AsyncRateLimitStorage;
    timeSource: TimeSource;
    maxKeyLength = DefaultMaxRateLimitKeyLength;
    audit: StoredFixedWindowAuditProc = nil
): AsyncStoredFixedWindow =
  ## Creates an async stored fixed-window limiter with an explicit time source.
  validatePrefix(prefix, maxKeyLength)
  validateFixedWindowConfig(limit, per)
  storage.validateAsyncStorageProc()
  AsyncStoredFixedWindow(
    prefix: prefix,
    limit: limit,
    per: per,
    maxKeyLength: maxKeyLength,
    storage: storage,
    timeSource: timeSource,
    audit: audit
  )

proc initAsyncStoredFixedWindow*(
    prefix: string;
    limit: int;
    per: Duration;
    storage: AsyncRateLimitStorage;
    maxKeyLength = DefaultMaxRateLimitKeyLength;
    audit: StoredFixedWindowAuditProc = nil
): AsyncStoredFixedWindow =
  ## Creates an async stored fixed-window limiter using the system clock.
  initAsyncStoredFixedWindow(
    prefix = prefix,
    limit = limit,
    per = per,
    storage = storage,
    timeSource = initTimeSource(),
    maxKeyLength = maxKeyLength,
    audit = audit
  )

proc inspect*(
    limiter: AsyncStoredFixedWindow;
    key: string;
    cost = 1
): Future[RateLimitResult] {.async.} =
  ## Checks a key asynchronously without consuming quota.
  validateCost(limiter.limit, cost)
  let fullKey = limiter.storageKey(key)
  result = await limiter.storage.inspectFixedWindow(
    fullKey,
    limiter.limit,
    limiter.per,
    cost,
    limiter.timeSource.now()
  )
  if not limiter.audit.isNil:
    limiter.audit(StoredFixedWindowAuditEvent(action: sfwaInspect, key: fullKey, result: result))

proc consume*(
    limiter: AsyncStoredFixedWindow;
    key: string;
    cost = 1
): Future[RateLimitResult] {.async.} =
  ## Checks and consumes quota asynchronously for a key.
  validateCost(limiter.limit, cost)
  let fullKey = limiter.storageKey(key)
  result = await limiter.storage.consumeFixedWindow(
    fullKey,
    limiter.limit,
    limiter.per,
    cost,
    limiter.timeSource.now()
  )
  if not limiter.audit.isNil:
    limiter.audit(StoredFixedWindowAuditEvent(action: sfwaConsume, key: fullKey, result: result))

proc allow*(
    limiter: AsyncStoredFixedWindow;
    key: string;
    cost = 1
): Future[bool] {.async.} =
  ## Convenience boolean wrapper around async `consume`.
  let decision = await limiter.consume(key, cost)
  decision.allowed

proc clear*(limiter: AsyncStoredFixedWindow; key: string): Future[bool] {.async.} =
  ## Removes one key from async storage.
  let fullKey = limiter.storageKey(key)
  result = await limiter.storage.clearFixedWindow(fullKey)
  if not limiter.audit.isNil:
    limiter.audit(StoredFixedWindowAuditEvent(action: sfwaClear, key: fullKey, cleared: result))
