import std/[times, unittest]

import flowbrigade

suite "policy presets":
  test "api client retry preset is bounded":
    let policy = apiClientRetryPolicy()

    check policy.delayFor(1) >= initDuration()
    check policy.delayFor(20) <= 5.sec

  test "worker retry preset is bounded":
    let policy = workerRetryPolicy()

    check policy.delayFor(1) >= 500.ms
    check policy.delayFor(20) <= 30.sec

  test "retry config presets include attempts":
    check apiClientRetryConfig().maxAttempts == 3
    check workerRetryConfig().maxAttempts == 5

  test "rate limit presets build usable limiters":
    var strict = initFixedWindow(strictRateLimitConfig(limit = 1, per = 1.min))
    check strict.allow()
    check not strict.allow()

    var lenient = initTokenBucket(lenientRateLimitConfig(rate = 1, per = 1.sec, burst = 1))
    check lenient.allow()
    check not lenient.allow()

  test "quota presets build usable ledgers":
    var daily = initBudgetLedger(dailyQuotaConfig(2))
    var monthly = initBudgetLedger(monthlyQuotaConfig(3))

    check daily.period == 1.day
    check monthly.period == 30.day
    check daily.allow("tenant:1", 2)
    check not daily.allow("tenant:1", 1)
    check monthly.allow("tenant:1", 3)
    check not monthly.allow("tenant:1", 1)

  test "circuit breaker preset builds usable breaker":
    var breaker = initCircuitBreaker(strictCircuitBreakerConfig(
      failureThreshold = 1,
      resetAfter = 1.sec
    ))

    check breaker.allow()
    breaker.recordFailure()
    check not breaker.allow()
