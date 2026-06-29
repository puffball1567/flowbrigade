import std/times

import ./backoff
import ./budget
import ./circuit_breaker
import ./ratelimit

type
  FlowBrigadeConfigError* = object of ValueError

  RetryConfig* = object
    policy*: BackoffPolicy
    maxAttempts*: int

  TokenBucketConfig* = object
    rate*: int
    per*: Duration
    burst*: int

  FixedWindowConfig* = object
    limit*: int
    per*: Duration

  SlidingWindowConfig* = object
    limit*: int
    per*: Duration

  KeyedFixedWindowConfig* = object
    limit*: int
    per*: Duration
    maxKeys*: int

  BudgetConfig* = object
    limit*: int64
    per*: Duration

  CircuitBreakerConfig* = object
    failureThreshold*: int
    resetAfter*: Duration

proc ensurePositive(name: string; value: int) =
  if value <= 0:
    raise newException(FlowBrigadeConfigError, name & " must be positive")

proc ensurePositive(name: string; value: int64) =
  if value <= 0:
    raise newException(FlowBrigadeConfigError, name & " must be positive")

proc ensurePositive(name: string; value: Duration) =
  if value <= initDuration():
    raise newException(FlowBrigadeConfigError, name & " must be positive")

proc initRetryConfig*(policy: BackoffPolicy; maxAttempts: int): RetryConfig =
  ensurePositive("maxAttempts", maxAttempts)
  RetryConfig(policy: policy, maxAttempts: maxAttempts)

proc initTokenBucketConfig*(rate: int; per: Duration; burst: int): TokenBucketConfig =
  ensurePositive("rate", rate)
  ensurePositive("per", per)
  ensurePositive("burst", burst)
  TokenBucketConfig(rate: rate, per: per, burst: burst)

proc initFixedWindowConfig*(limit: int; per: Duration): FixedWindowConfig =
  ensurePositive("limit", limit)
  ensurePositive("per", per)
  FixedWindowConfig(limit: limit, per: per)

proc initSlidingWindowConfig*(limit: int; per: Duration): SlidingWindowConfig =
  ensurePositive("limit", limit)
  ensurePositive("per", per)
  SlidingWindowConfig(limit: limit, per: per)

proc initKeyedFixedWindowConfig*(
    limit: int;
    per: Duration;
    maxKeys = DefaultMaxKeys
): KeyedFixedWindowConfig =
  ensurePositive("limit", limit)
  ensurePositive("per", per)
  ensurePositive("maxKeys", maxKeys)
  KeyedFixedWindowConfig(limit: limit, per: per, maxKeys: maxKeys)

proc initBudgetConfig*(limit: int64; per: Duration): BudgetConfig =
  ensurePositive("limit", limit)
  ensurePositive("per", per)
  BudgetConfig(limit: limit, per: per)

proc initBudgetConfig*(limit: int; per: Duration): BudgetConfig =
  initBudgetConfig(limit.int64, per)

proc initCircuitBreakerConfig*(
    failureThreshold: int;
    resetAfter: Duration
): CircuitBreakerConfig =
  ensurePositive("failureThreshold", failureThreshold)
  ensurePositive("resetAfter", resetAfter)
  CircuitBreakerConfig(failureThreshold: failureThreshold, resetAfter: resetAfter)

proc initTokenBucket*(config: TokenBucketConfig): TokenBucket =
  initTokenBucket(rate = config.rate, per = config.per, burst = config.burst)

proc initFixedWindow*(config: FixedWindowConfig): FixedWindow =
  initFixedWindow(limit = config.limit, per = config.per)

proc initSlidingWindow*(config: SlidingWindowConfig): SlidingWindow =
  initSlidingWindow(limit = config.limit, per = config.per)

proc initKeyedFixedWindow*[K](config: KeyedFixedWindowConfig): KeyedFixedWindow[K] =
  initKeyedFixedWindow[K](
    limit = config.limit,
    per = config.per,
    maxKeys = config.maxKeys
  )

proc initBudgetLedger*(config: BudgetConfig): BudgetLedger =
  initBudgetLedger(limit = config.limit, per = config.per)

proc initCircuitBreaker*(config: CircuitBreakerConfig): CircuitBreaker =
  initCircuitBreaker(
    failureThreshold = config.failureThreshold,
    resetAfter = config.resetAfter
  )
