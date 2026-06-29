import ./backoff
import ./config
import ./durations

proc apiClientRetryPolicy*(): BackoffPolicy =
  expBackoff(
    initial = 100.ms,
    factor = 2.0,
    maxDelay = 5.sec,
    jitter = fullJitter
  )

proc workerRetryPolicy*(): BackoffPolicy =
  expBackoff(
    initial = 500.ms,
    factor = 2.0,
    maxDelay = 30.sec,
    jitter = decorrelatedJitter
  )

proc apiClientRetryConfig*(): RetryConfig =
  initRetryConfig(policy = apiClientRetryPolicy(), maxAttempts = 3)

proc workerRetryConfig*(): RetryConfig =
  initRetryConfig(policy = workerRetryPolicy(), maxAttempts = 5)

proc strictRateLimitConfig*(limit = 60; per = 1.min): FixedWindowConfig =
  initFixedWindowConfig(limit = limit, per = per)

proc dailyQuotaConfig*(limit: int64): BudgetConfig =
  initBudgetConfig(limit = limit, per = 1.day)

proc dailyQuotaConfig*(limit: int): BudgetConfig =
  dailyQuotaConfig(limit.int64)

proc monthlyQuotaConfig*(limit: int64): BudgetConfig =
  initBudgetConfig(limit = limit, per = 30.day)

proc monthlyQuotaConfig*(limit: int): BudgetConfig =
  monthlyQuotaConfig(limit.int64)

proc lenientRateLimitConfig*(
    rate = 10;
    per = 1.sec;
    burst = 20
): TokenBucketConfig =
  initTokenBucketConfig(rate = rate, per = per, burst = burst)

proc strictCircuitBreakerConfig*(
    failureThreshold = 3;
    resetAfter = 30.sec
): CircuitBreakerConfig =
  initCircuitBreakerConfig(
    failureThreshold = failureThreshold,
    resetAfter = resetAfter
  )
