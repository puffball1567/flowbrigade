import std/[times, unittest]

import flowbrigade

suite "configuration objects":
  test "builds retry config":
    let config = initRetryConfig(
      policy = fixedBackoff(100.ms),
      maxAttempts = 3
    )

    check config.maxAttempts == 3
    check config.policy.delayFor(1) == 100.ms

  test "rejects invalid retry config":
    expect FlowBrigadeConfigError:
      discard initRetryConfig(
        policy = fixedBackoff(100.ms),
        maxAttempts = 0
      )

  test "builds token bucket from config":
    var limiter = initTokenBucket(initTokenBucketConfig(
      rate = 2,
      per = 1.sec,
      burst = 2
    ))

    check limiter.allow()
    check limiter.allow()
    check not limiter.allow()

  test "builds fixed window from config":
    var limiter = initFixedWindow(initFixedWindowConfig(
      limit = 1,
      per = 1.min
    ))

    check limiter.allow()
    check not limiter.allow()

  test "builds sliding window from config":
    var limiter = initSlidingWindow(initSlidingWindowConfig(
      limit = 1,
      per = 1.min
    ))

    check limiter.allow()
    check not limiter.allow()

  test "builds keyed fixed window from config":
    var limiter = initKeyedFixedWindow[string](initKeyedFixedWindowConfig(
      limit = 1,
      per = 1.min,
      maxKeys = 2
    ))

    check limiter.allow("user:1")
    check not limiter.allow("user:1")
    check limiter.allow("user:2")

  test "builds budget ledger from config":
    var ledger = initBudgetLedger(initBudgetConfig(
      limit = 3,
      per = 1.hr
    ))

    check ledger.allow("tenant:1", 3)
    check not ledger.allow("tenant:1", 1)

  test "builds circuit breaker from config":
    var breaker = initCircuitBreaker(initCircuitBreakerConfig(
      failureThreshold = 1,
      resetAfter = 1.sec
    ))

    check breaker.allow()
    breaker.recordFailure()
    check not breaker.allow()

  test "rejects invalid configs before constructor dispatch":
    expect FlowBrigadeConfigError:
      discard initTokenBucketConfig(rate = 0, per = 1.sec, burst = 1)
    expect FlowBrigadeConfigError:
      discard initFixedWindowConfig(limit = 1, per = initDuration())
    expect FlowBrigadeConfigError:
      discard initSlidingWindowConfig(limit = 0, per = 1.sec)
    expect FlowBrigadeConfigError:
      discard initKeyedFixedWindowConfig(limit = 1, per = 1.sec, maxKeys = 0)
    expect FlowBrigadeConfigError:
      discard initBudgetConfig(limit = 0, per = 1.hr)
    expect FlowBrigadeConfigError:
      discard initCircuitBreakerConfig(failureThreshold = 0, resetAfter = 1.sec)
