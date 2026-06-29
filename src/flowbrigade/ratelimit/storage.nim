import std/[strutils, tables, times]

import ../internal/time_source
import ./errors
import ./keyed
import ./result

const DefaultMaxRateLimitKeyLength* = 512

type
  ## Stored fixed-window operation recorded by the audit hook.
  StoredFixedWindowAction* = enum
    sfwaInspect, sfwaConsume, sfwaClear

  ## Audit event emitted after a stored fixed-window operation.
  StoredFixedWindowAuditEvent* = object
    action*: StoredFixedWindowAction
    key*: string
    result*: RateLimitResult
    cleared*: bool

  ## Optional audit hook for stored fixed-window operations.
  StoredFixedWindowAuditProc* = proc(event: StoredFixedWindowAuditEvent) {.closure.}

  ## Storage callback used by stored fixed-window limiters.
  ##
  ## `current` is supplied by FlowBrigade so adapters can be deterministic in
  ## tests. External storage adapters must keep consume operations atomic.
  FixedWindowStorageProc* = proc(
    key: string;
    limit: int;
    per: Duration;
    cost: int;
    current: Duration
  ): RateLimitResult {.closure.}

  ## Removes one stored fixed-window key and returns whether it existed.
  ClearFixedWindowStorageProc* = proc(key: string): bool {.closure.}

  ## Callback bundle for fixed-window storage adapters.
  RateLimitStorage* = object
    inspectFixedWindow*: FixedWindowStorageProc
    consumeFixedWindow*: FixedWindowStorageProc
    clearFixedWindow*: ClearFixedWindowStorageProc

  ## Fixed-window limiter backed by a storage adapter.
  StoredFixedWindow* = object
    prefix: string
    limit: int
    per: Duration
    maxKeyLength: int
    storage: RateLimitStorage
    timeSource: TimeSource
    audit: StoredFixedWindowAuditProc

  StoredWindowState = object
    used: int
    windowStart: Duration

  ## In-memory storage adapter with a bounded key count.
  InMemoryRateLimitStorage* = ref object
    maxKeys: int
    entries: Table[string, StoredWindowState]

proc validateStorageProc(storage: RateLimitStorage) =
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

proc validateMaxKeyLength(maxKeyLength: int) =
  if maxKeyLength <= 0:
    raise newException(RateLimitConfigError, "maxKeyLength must be positive")

proc hasControlChar(value: string): bool =
  for ch in value:
    if ord(ch) < 32 or ord(ch) == 127:
      return true
  false

proc validateKeyPart(name, value: string; maxLength: int) =
  if value.len == 0:
    raise newException(RateLimitError, name & " must not be empty")
  if value.len > maxLength:
    raise newException(RateLimitError, name & " is too long")
  if value.strip().len == 0:
    raise newException(RateLimitError, name & " must not be blank")
  if value.hasControlChar():
    raise newException(RateLimitError, name & " must not contain control characters")

proc validatePrefix(prefix: string; maxKeyLength: int) =
  if prefix.len == 0 or prefix.strip().len == 0:
    raise newException(RateLimitConfigError, "prefix must not be blank")
  if prefix.len > maxKeyLength:
    raise newException(RateLimitConfigError, "prefix is too long")
  if prefix.hasControlChar():
    raise newException(RateLimitConfigError, "prefix must not contain control characters")

proc validateCost(limit, cost: int) =
  if cost <= 0:
    raise newException(RateLimitError, "cost must be positive")
  if cost > limit:
    raise newException(RateLimitError, "cost must not exceed window limit")

proc fixedWindowResult(
    limit: int;
    per: Duration;
    used: int;
    windowStart: Duration;
    cost: int;
    current: Duration
): RateLimitResult =
  let remaining = limit - used
  let resetAfter = max(initDuration(), per - (current - windowStart))
  if used + cost <= limit:
    return allowedResult(
      limit = limit,
      remaining = remaining - cost,
      resetAfter = resetAfter
    )

  deniedResult(
    limit = limit,
    remaining = remaining,
    retryAfter = resetAfter,
    resetAfter = resetAfter
  )

proc pruneExpired(storage: InMemoryRateLimitStorage; per, current: Duration) =
  var expired: seq[string] = @[]
  for key, state in storage.entries.pairs:
    if current - state.windowStart >= per:
      expired.add(key)
  for key in expired:
    storage.entries.del(key)

proc stateFor(
    storage: InMemoryRateLimitStorage;
    key: string;
    per, current: Duration
): StoredWindowState =
  result = storage.entries.getOrDefault(key, StoredWindowState(windowStart: current))
  if current - result.windowStart >= per:
    result.windowStart = current
    result.used = 0

proc inspectStoredFixedWindow(
    storage: InMemoryRateLimitStorage;
    key: string;
    limit: int;
    per: Duration;
    cost: int;
    current: Duration
): RateLimitResult =
  validateFixedWindowConfig(limit, per)
  validateCost(limit, cost)
  let state = storage.stateFor(key, per, current)
  fixedWindowResult(limit, per, state.used, state.windowStart, cost, current)

proc consumeStoredFixedWindow(
    storage: InMemoryRateLimitStorage;
    key: string;
    limit: int;
    per: Duration;
    cost: int;
    current: Duration
): RateLimitResult =
  validateFixedWindowConfig(limit, per)
  validateCost(limit, cost)

  let isNewKey = not storage.entries.hasKey(key)
  if isNewKey and storage.entries.len >= storage.maxKeys:
    storage.pruneExpired(per, current)
    if storage.entries.len >= storage.maxKeys:
      raise newException(RateLimitError, "storage key capacity exceeded")

  var state = storage.stateFor(key, per, current)
  let checked = fixedWindowResult(limit, per, state.used, state.windowStart, cost, current)
  if checked.allowed:
    state.used += cost
  storage.entries[key] = state
  checked

proc clearStoredFixedWindow(storage: InMemoryRateLimitStorage; key: string): bool =
  result = storage.entries.hasKey(key)
  storage.entries.del(key)

proc initInMemoryRateLimitStorage*(
    maxKeys = DefaultMaxKeys
): InMemoryRateLimitStorage =
  ## Creates bounded in-memory storage for stored fixed-window limiters.
  ##
  ## This adapter is useful for tests and single-process tools. Use a shared
  ## external adapter when limits must be enforced across processes.
  if maxKeys <= 0:
    raise newException(RateLimitConfigError, "maxKeys must be positive")
  InMemoryRateLimitStorage(maxKeys: maxKeys, entries: initTable[string, StoredWindowState]())

proc asRateLimitStorage*(storage: InMemoryRateLimitStorage): RateLimitStorage =
  ## Converts in-memory storage into the generic storage callback bundle.
  if storage.isNil:
    raise newException(RateLimitConfigError, "storage must not be nil")
  RateLimitStorage(
    inspectFixedWindow: proc(
      key: string;
      limit: int;
      per: Duration;
      cost: int;
      current: Duration
    ): RateLimitResult =
      storage.inspectStoredFixedWindow(key, limit, per, cost, current),
    consumeFixedWindow: proc(
      key: string;
      limit: int;
      per: Duration;
      cost: int;
      current: Duration
    ): RateLimitResult =
      storage.consumeStoredFixedWindow(key, limit, per, cost, current),
    clearFixedWindow: proc(key: string): bool =
      storage.clearStoredFixedWindow(key)
  )

proc initStoredFixedWindow*(
    prefix: string;
    limit: int;
    per: Duration;
    storage: RateLimitStorage;
    timeSource: TimeSource;
    maxKeyLength = DefaultMaxRateLimitKeyLength;
    audit: StoredFixedWindowAuditProc = nil
): StoredFixedWindow =
  ## Creates a stored fixed-window limiter with an explicit time source.
  ##
  ## `prefix` namespaces keys in the storage adapter. The `maxKeyLength` guard
  ## rejects unexpectedly large keys before they reach external systems.
  validateMaxKeyLength(maxKeyLength)
  validatePrefix(prefix, maxKeyLength)
  validateFixedWindowConfig(limit, per)
  storage.validateStorageProc()
  StoredFixedWindow(
    prefix: prefix,
    limit: limit,
    per: per,
    maxKeyLength: maxKeyLength,
    storage: storage,
    timeSource: timeSource,
    audit: audit
  )

proc initStoredFixedWindow*(
    prefix: string;
    limit: int;
    per: Duration;
    storage: RateLimitStorage;
    maxKeyLength = DefaultMaxRateLimitKeyLength;
    audit: StoredFixedWindowAuditProc = nil
): StoredFixedWindow =
  ## Creates a stored fixed-window limiter using the system clock.
  initStoredFixedWindow(
    prefix = prefix,
    limit = limit,
    per = per,
    storage = storage,
    timeSource = initTimeSource(),
    maxKeyLength = maxKeyLength,
    audit = audit
  )

proc storageKey(limiter: StoredFixedWindow; key: string): string =
  validateKeyPart("key", key, limiter.maxKeyLength)
  limiter.prefix & ":" & key

proc inspect*(limiter: StoredFixedWindow; key: string; cost = 1): RateLimitResult =
  ## Checks a key without consuming quota.
  validateCost(limiter.limit, cost)
  let fullKey = limiter.storageKey(key)
  result = limiter.storage.inspectFixedWindow(
    fullKey,
    limiter.limit,
    limiter.per,
    cost,
    limiter.timeSource.now()
  )
  if not limiter.audit.isNil:
    limiter.audit(StoredFixedWindowAuditEvent(action: sfwaInspect, key: fullKey, result: result))

proc consume*(limiter: StoredFixedWindow; key: string; cost = 1): RateLimitResult =
  ## Checks and consumes quota for a key.
  validateCost(limiter.limit, cost)
  let fullKey = limiter.storageKey(key)
  result = limiter.storage.consumeFixedWindow(
    fullKey,
    limiter.limit,
    limiter.per,
    cost,
    limiter.timeSource.now()
  )
  if not limiter.audit.isNil:
    limiter.audit(StoredFixedWindowAuditEvent(action: sfwaConsume, key: fullKey, result: result))

proc allow*(limiter: StoredFixedWindow; key: string; cost = 1): bool =
  ## Convenience boolean wrapper around `consume`.
  limiter.consume(key, cost).allowed

proc clear*(limiter: StoredFixedWindow; key: string): bool =
  ## Removes one key from storage.
  ##
  ## This is intended for operational cleanup and tests. Do not expose it
  ## directly to untrusted callers.
  let fullKey = limiter.storageKey(key)
  result = limiter.storage.clearFixedWindow(fullKey)
  if not limiter.audit.isNil:
    limiter.audit(StoredFixedWindowAuditEvent(action: sfwaClear, key: fullKey, cleared: result))
