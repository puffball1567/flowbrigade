import std/[strutils, tables, times]

import ./internal/time_source

type
  BudgetError* = object of ValueError
  BudgetConfigError* = object of ValueError

  BudgetResult* = object
    allowed*: bool
    key*: string
    limit*: int64
    used*: int64
    remaining*: int64
    cost*: int64
    retryAfter*: Duration
    resetAfter*: Duration

  BudgetEventKind* = enum
    budgetInspect
    budgetConsume
    budgetRefund
    budgetReset

  BudgetEvent* = object
    kind*: BudgetEventKind
    key*: string
    amount*: int64
    result*: BudgetResult

  BudgetEntry = object
    used: int64
    windowStart: Duration

  BudgetLedger* = object
    limit: int64
    per: Duration
    entries: Table[string, BudgetEntry]
    timeSource: TimeSource

proc allowedBudgetResult*(
    key: string;
    limit, used, cost: int64;
    resetAfter: Duration
): BudgetResult =
  BudgetResult(
    allowed: true,
    key: key,
    limit: limit,
    used: used + cost,
    remaining: max(0'i64, limit - used - cost),
    cost: cost,
    retryAfter: initDuration(),
    resetAfter: resetAfter
  )

proc deniedBudgetResult*(
    key: string;
    limit, used, cost: int64;
    retryAfter, resetAfter: Duration
): BudgetResult =
  BudgetResult(
    allowed: false,
    key: key,
    limit: limit,
    used: used,
    remaining: max(0'i64, limit - used),
    cost: cost,
    retryAfter: retryAfter,
    resetAfter: resetAfter
  )

proc validateConfig(limit: int64; per: Duration) =
  if limit <= 0:
    raise newException(BudgetConfigError, "limit must be positive")
  if per <= initDuration():
    raise newException(BudgetConfigError, "per must be positive")

proc normalizeKey(key: string): string =
  result = key.strip()
  if result.len == 0:
    raise newException(BudgetError, "key must not be empty")

proc validateAmount(name: string; value: int64) =
  if value <= 0:
    raise newException(BudgetError, name & " must be positive")

proc initBudgetLedger*(
    limit: int64;
    per: Duration;
    timeSource: TimeSource
): BudgetLedger =
  validateConfig(limit, per)
  BudgetLedger(
    limit: limit,
    per: per,
    entries: initTable[string, BudgetEntry](),
    timeSource: timeSource
  )

proc initBudgetLedger*(limit: int64; per: Duration): BudgetLedger =
  initBudgetLedger(limit = limit, per = per, timeSource = initTimeSource())

proc initBudgetLedger*(limit: int; per: Duration): BudgetLedger =
  initBudgetLedger(limit = limit.int64, per = per)

proc resetIfNeeded(ledger: var BudgetLedger; key: string) =
  let current = ledger.timeSource.now()
  if not ledger.entries.hasKey(key):
    ledger.entries[key] = BudgetEntry(windowStart: current)
    return
  if current - ledger.entries[key].windowStart >= ledger.per:
    ledger.entries[key] = BudgetEntry(windowStart: current)

proc windowRemaining(ledger: BudgetLedger; key: string): Duration =
  if not ledger.entries.hasKey(key):
    return ledger.per
  let elapsed = ledger.timeSource.now() - ledger.entries[key].windowStart
  max(initDuration(), ledger.per - elapsed)

proc inspect*(ledger: var BudgetLedger; key: string; cost: int64 = 1): BudgetResult =
  let normalized = normalizeKey(key)
  validateAmount("cost", cost)
  ledger.resetIfNeeded(normalized)
  let entry = ledger.entries[normalized]
  let resetAfter = ledger.windowRemaining(normalized)
  if entry.used + cost <= ledger.limit:
    return allowedBudgetResult(
      key = normalized,
      limit = ledger.limit,
      used = entry.used,
      cost = cost,
      resetAfter = resetAfter
    )
  deniedBudgetResult(
    key = normalized,
    limit = ledger.limit,
    used = entry.used,
    cost = cost,
    retryAfter = resetAfter,
    resetAfter = resetAfter
  )

proc inspect*(ledger: var BudgetLedger; key: string; cost: int): BudgetResult =
  ledger.inspect(key, cost.int64)

proc consume*(ledger: var BudgetLedger; key: string; cost: int64 = 1): BudgetResult =
  result = ledger.inspect(key, cost)
  if result.allowed:
    ledger.entries[result.key].used = result.used

proc consume*(ledger: var BudgetLedger; key: string; cost: int): BudgetResult =
  ledger.consume(key, cost.int64)

proc allow*(ledger: var BudgetLedger; key: string; cost: int64 = 1): bool =
  ledger.consume(key, cost).allowed

proc allow*(ledger: var BudgetLedger; key: string; cost: int): bool =
  ledger.allow(key, cost.int64)

proc refund*(ledger: var BudgetLedger; key: string; amount: int64): BudgetResult =
  let normalized = normalizeKey(key)
  validateAmount("amount", amount)
  ledger.resetIfNeeded(normalized)
  ledger.entries[normalized].used = max(0'i64, ledger.entries[normalized].used - amount)
  allowedBudgetResult(
    key = normalized,
    limit = ledger.limit,
    used = ledger.entries[normalized].used,
    cost = 0,
    resetAfter = ledger.windowRemaining(normalized)
  )

proc refund*(ledger: var BudgetLedger; key: string; amount: int): BudgetResult =
  ledger.refund(key, amount.int64)

proc reset*(ledger: var BudgetLedger; key: string): BudgetResult =
  let normalized = normalizeKey(key)
  ledger.entries[normalized] = BudgetEntry(windowStart: ledger.timeSource.now())
  allowedBudgetResult(
    key = normalized,
    limit = ledger.limit,
    used = 0,
    cost = 0,
    resetAfter = ledger.per
  )

proc resetAll*(ledger: var BudgetLedger) =
  ledger.entries.clear()

proc limit*(ledger: BudgetLedger): int64 =
  ledger.limit

proc period*(ledger: BudgetLedger): Duration =
  ledger.per
