import std/[math, strutils, tables, times]

import ./internal/time_source

const DefaultRetryAllowanceMaxKeys* = 65_536

type
  RetryAllowanceError* = object of ValueError
  RetryAllowanceConfigError* = object of ValueError

  RetryAllowanceResult* = object
    allowed*: bool
    key*: string
    limit*: int64
    originals*: int64
    retries*: int64
    remaining*: int64
    cost*: int64
    retryAfter*: Duration
    resetAfter*: Duration

  RetryAllowanceEventKind* = enum
    retryAllowanceOriginal,
    retryAllowanceInspect,
    retryAllowanceConsume,
    retryAllowanceReset

  RetryAllowanceEvent* = object
    kind*: RetryAllowanceEventKind
    key*: string
    amount*: int64
    result*: RetryAllowanceResult

  RetryAllowanceEntry = object
    originals: int64
    retries: int64
    windowStart: Duration

  RetryAllowance* = object
    retryRatio: float
    minimumRetries: int64
    per: Duration
    maxKeys: int
    entries: Table[string, RetryAllowanceEntry]
    timeSource: TimeSource

proc normalizeKey(key: string): string =
  for ch in key:
    if ord(ch) < 32 or ord(ch) == 127:
      raise newException(RetryAllowanceError, "key must not contain control characters")
  result = key.strip()
  if result.len == 0:
    raise newException(RetryAllowanceError, "key must not be empty")

proc validateAmount(name: string; value: int64) =
  if value <= 0:
    raise newException(RetryAllowanceError, name & " must be positive")

proc validateConfig(retryRatio: float; minimumRetries: int64; per: Duration; maxKeys: int) =
  if retryRatio < 0.0 or retryRatio > 1.0 or classify(retryRatio) in {fcNan, fcInf, fcNegInf}:
    raise newException(RetryAllowanceConfigError, "retryRatio must be between 0.0 and 1.0")
  if minimumRetries < 0:
    raise newException(RetryAllowanceConfigError, "minimumRetries must not be negative")
  if per <= initDuration():
    raise newException(RetryAllowanceConfigError, "per must be positive")
  if maxKeys <= 0:
    raise newException(RetryAllowanceConfigError, "maxKeys must be positive")

proc initRetryAllowance*(
    retryRatio: float;
    per: Duration;
    minimumRetries: int64 = 0;
    timeSource: TimeSource;
    maxKeys = DefaultRetryAllowanceMaxKeys
): RetryAllowance =
  ## Creates a keyed retry allowance.
  ##
  ## Callers record original requests, then consume retry allowance only when a
  ## retry is about to be attempted. This helps prevent retry storms without
  ## coupling FlowBrigade to a specific client, workflow engine, or transport.
  if timeSource.isNil:
    raise newException(RetryAllowanceConfigError, "timeSource must not be nil")
  validateConfig(retryRatio, minimumRetries, per, maxKeys)
  RetryAllowance(
    retryRatio: retryRatio,
    minimumRetries: minimumRetries,
    per: per,
    maxKeys: maxKeys,
    entries: initTable[string, RetryAllowanceEntry](),
    timeSource: timeSource
  )

proc initRetryAllowance*(
    retryRatio: float;
    per: Duration;
    minimumRetries: int64 = 0;
    maxKeys = DefaultRetryAllowanceMaxKeys
): RetryAllowance =
  initRetryAllowance(
    retryRatio = retryRatio,
    per = per,
    minimumRetries = minimumRetries,
    timeSource = initTimeSource(),
    maxKeys = maxKeys
  )

proc initRetryAllowance*(
    retryRatio: float;
    per: Duration;
    minimumRetries: int;
    maxKeys = DefaultRetryAllowanceMaxKeys
): RetryAllowance =
  initRetryAllowance(
    retryRatio = retryRatio,
    per = per,
    minimumRetries = minimumRetries.int64,
    maxKeys = maxKeys
  )

proc resetIfExpired(allowance: var RetryAllowance; key: string; current: Duration) =
  if not allowance.entries.hasKey(key):
    return
  if current - allowance.entries[key].windowStart >= allowance.per:
    allowance.entries.del(key)

proc pruneExpired(allowance: var RetryAllowance; current: Duration) =
  var expired: seq[string] = @[]
  for key, entry in allowance.entries.pairs:
    if current - entry.windowStart >= allowance.per:
      expired.add(key)
  for key in expired:
    allowance.entries.del(key)

proc ensureKeyCapacity(allowance: var RetryAllowance; key: string; current: Duration) =
  if allowance.entries.hasKey(key):
    return
  if allowance.entries.len >= allowance.maxKeys:
    allowance.pruneExpired(current)
    if allowance.entries.len >= allowance.maxKeys:
      raise newException(RetryAllowanceError, "key capacity exceeded")

proc windowRemaining(allowance: RetryAllowance; entry: RetryAllowanceEntry; current: Duration): Duration =
  max(initDuration(), allowance.per - (current - entry.windowStart))

proc retryLimit(allowance: RetryAllowance; originals: int64): int64 =
  allowance.minimumRetries + int64(floor(float(originals) * allowance.retryRatio))

proc resultFor(
    allowance: RetryAllowance;
    key: string;
    entry: RetryAllowanceEntry;
    current: Duration;
    cost: int64
): RetryAllowanceResult =
  let limit = allowance.retryLimit(entry.originals)
  let resetAfter = allowance.windowRemaining(entry, current)
  if entry.retries + cost <= limit:
    return RetryAllowanceResult(
      allowed: true,
      key: key,
      limit: limit,
      originals: entry.originals,
      retries: entry.retries + cost,
      remaining: max(0'i64, limit - entry.retries - cost),
      cost: cost,
      retryAfter: initDuration(),
      resetAfter: resetAfter
    )

  RetryAllowanceResult(
    allowed: false,
    key: key,
    limit: limit,
    originals: entry.originals,
    retries: entry.retries,
    remaining: max(0'i64, limit - entry.retries),
    cost: cost,
    retryAfter: resetAfter,
    resetAfter: resetAfter
  )

proc emptyEntry(current: Duration): RetryAllowanceEntry =
  RetryAllowanceEntry(windowStart: current)

proc entryFor(allowance: RetryAllowance; key: string; current: Duration): RetryAllowanceEntry =
  allowance.entries.getOrDefault(key, emptyEntry(current))

proc recordOriginal*(allowance: var RetryAllowance; key: string; amount: int64 = 1): RetryAllowanceResult =
  ## Records original, non-retry work for one key and returns current retry
  ## allowance metadata. This does not consume retry allowance.
  let normalized = normalizeKey(key)
  validateAmount("amount", amount)
  let current = allowance.timeSource.now()
  allowance.resetIfExpired(normalized, current)
  allowance.ensureKeyCapacity(normalized, current)
  var entry = allowance.entryFor(normalized, current)
  entry.originals += amount
  allowance.entries[normalized] = entry
  RetryAllowanceResult(
    allowed: true,
    key: normalized,
    limit: allowance.retryLimit(entry.originals),
    originals: entry.originals,
    retries: entry.retries,
    remaining: max(0'i64, allowance.retryLimit(entry.originals) - entry.retries),
    cost: 0,
    retryAfter: initDuration(),
    resetAfter: allowance.windowRemaining(entry, current)
  )

proc recordOriginal*(allowance: var RetryAllowance; key: string; amount: int): RetryAllowanceResult =
  allowance.recordOriginal(key, amount.int64)

proc inspectRetry*(allowance: var RetryAllowance; key: string; cost: int64 = 1): RetryAllowanceResult =
  ## Checks whether retry allowance is available without consuming it.
  let normalized = normalizeKey(key)
  validateAmount("cost", cost)
  let current = allowance.timeSource.now()
  allowance.resetIfExpired(normalized, current)
  let entry = allowance.entryFor(normalized, current)
  allowance.resultFor(normalized, entry, current, cost)

proc inspectRetry*(allowance: var RetryAllowance; key: string; cost: int): RetryAllowanceResult =
  allowance.inspectRetry(key, cost.int64)

proc recordRetry*(allowance: var RetryAllowance; key: string; cost: int64 = 1): RetryAllowanceResult =
  ## Checks and consumes retry allowance for one key.
  let normalized = normalizeKey(key)
  validateAmount("cost", cost)
  let current = allowance.timeSource.now()
  allowance.resetIfExpired(normalized, current)
  var entry = allowance.entryFor(normalized, current)
  let checked = allowance.resultFor(normalized, entry, current, cost)
  if checked.allowed:
    allowance.ensureKeyCapacity(normalized, current)
    entry.retries = checked.retries
    allowance.entries[normalized] = entry
  checked

proc recordRetry*(allowance: var RetryAllowance; key: string; cost: int): RetryAllowanceResult =
  allowance.recordRetry(key, cost.int64)

proc allowRetry*(allowance: var RetryAllowance; key: string; cost: int64 = 1): bool =
  allowance.recordRetry(key, cost).allowed

proc allowRetry*(allowance: var RetryAllowance; key: string; cost: int): bool =
  allowance.allowRetry(key, cost.int64)

proc clear*(allowance: var RetryAllowance; key: string): bool =
  let normalized = normalizeKey(key)
  result = allowance.entries.hasKey(normalized)
  allowance.entries.del(normalized)

proc reset*(allowance: var RetryAllowance; key: string): bool =
  allowance.clear(key)

proc resetAll*(allowance: var RetryAllowance): int =
  result = allowance.entries.len
  allowance.entries.clear()

proc pruneExpired*(allowance: var RetryAllowance) =
  allowance.pruneExpired(allowance.timeSource.now())

proc activeKeys*(allowance: var RetryAllowance): int =
  allowance.pruneExpired()
  allowance.entries.len

proc configuredRetryRatio*(allowance: RetryAllowance): float =
  allowance.retryRatio

proc configuredMinimumRetries*(allowance: RetryAllowance): int64 =
  allowance.minimumRetries

proc configuredPeriod*(allowance: RetryAllowance): Duration =
  allowance.per

proc keyCapacity*(allowance: RetryAllowance): int =
  allowance.maxKeys
