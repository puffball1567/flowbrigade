import std/unittest

import flowbrigade

suite "flow policies":
  test "API abuse policy combines identity and global limits":
    let policy = apiAbuseProtectionPolicy(
      perIdentityLimit = 2,
      perIdentityWindow = 1.min,
      globalRate = 10,
      globalPer = 1.sec,
      globalBurst = 10
    )

    check policy.kind == fpkApiAbuseProtection
    check policy.registry.hasLimiter(policy.primaryLimiter)
    check policy.allow("ip:127.0.0.1")
    check policy.allow("ip:127.0.0.1")
    check not policy.allow("ip:127.0.0.1")

  test "login policy applies account and identity guard limits":
    let policy = loginProtectionPolicy(
      accountLimit = 1,
      accountWindow = 1.min,
      identityLimit = 10,
      identityWindow = 1.hr
    )

    check policy.kind == fpkLoginProtection
    check policy.allow("account:42")
    check not policy.allow("account:42")

  test "password reset policy is stricter by default":
    let policy = passwordResetProtectionPolicy(
      accountLimit = 1,
      accountWindow = 1.hr,
      identityLimit = 5,
      identityWindow = 1.hr
    )

    check policy.kind == fpkPasswordResetProtection
    check policy.allow("account:42")
    check not policy.allow("account:42")

  test "third-party API client policy includes retry and circuit breaker config":
    let policy = thirdPartyApiClientPolicy(
      rate = 1,
      per = 1.sec,
      burst = 1,
      failureThreshold = 1,
      resetAfter = 1.sec
    )

    check policy.kind == fpkThirdPartyApiClient
    check policy.retry.maxAttempts == 3
    check policy.allow("vendor")
    check not policy.allow("vendor")

    var breaker = initCircuitBreaker(policy)
    check breaker.allow()
    breaker.recordFailure()
    check not breaker.allow()

  test "worker backpressure policy includes retry circuit and bulkhead config":
    let policy = workerBackpressurePolicy(
      rate = 1,
      per = 1.sec,
      burst = 1,
      concurrency = 2,
      failureThreshold = 1,
      resetAfter = 1.sec
    )

    check policy.kind == fpkWorkerBackpressure
    check policy.retry.maxAttempts == 5
    check policy.allow("worker")
    check not policy.allow("worker")

    var bulkhead = initBulkhead(policy)
    check bulkhead.tryAcquire()
    check bulkhead.tryAcquire()
    check not bulkhead.tryAcquire()

  test "multi-tenant quota policy combines burst and longer budget":
    let policy = multiTenantQuotaPolicy(
      quotaLimit = 3,
      quotaPeriod = 1.day,
      burstLimit = 2,
      burstWindow = 1.min
    )

    check policy.kind == fpkMultiTenantQuota
    check policy.allow("tenant:42")
    check policy.allow("tenant:42")
    check not policy.allow("tenant:42")

    var budget = initBudgetLedger(policy)
    check budget.allow("tenant:42", 3)
    check not budget.allow("tenant:42", 1)

  test "policies can merge named limiters into another registry":
    let policy = loginProtectionPolicy(name = "login")
    var registry = initLimiterRegistry()

    policy.mergeInto(registry)

    check registry.hasLimiter("login")
    check registry.hasLimiter("login_account")
    check registry.hasLimiter("login_identity")

  test "policies produce validation reports":
    let policy = workerBackpressurePolicy(
      name = "worker",
      rate = 2,
      per = 1.sec,
      burst = 4,
      concurrency = 3
    )

    let report = policy.validate()
    check report.valid
    check report.policyName == "worker"
    check report.limiterCount == 1
    check report.hasRetry
    check report.hasCircuitBreaker
    check report.hasBulkhead
    check not report.hasQuota
    check report.issues.len == 0

    let required = policy.require([fprRetry, fprCircuitBreaker, fprBulkhead])
    check required.valid

  test "policy validation reports missing or required components":
    var registry = initLimiterRegistry()
    registry.addLimiter("present", fixedWindowDefinition(limit = 1, per = 1.min))
    let broken = initFlowPolicy(
      kind = fpkWorkerBackpressure,
      name = "broken",
      primaryLimiter = "missing",
      registry = registry
    )

    let report = broken.validate()
    check not report.valid
    check report.issues.len == 1
    check report.issues[0].kind == fpviMissingLimiter
    check report.issues[0].path == "primaryLimiter"
    expect FlowPolicyConfigError:
      discard broken.requireValid()

    let policy = apiAbuseProtectionPolicy()
    expect FlowPolicyConfigError:
      discard policy.require([fprQuota])
    expect FlowPolicyConfigError:
      discard policy.require([fprRetry])

  test "policy validation reports invalid optional values":
    var policy = workerBackpressurePolicy()
    policy.bulkheadCapacity = -1

    let report = policy.validate()

    check not report.valid
    check report.issues.len == 1
    check report.issues[0].kind == fpviInvalidBulkhead
    check report.issues[0].path == "bulkheadCapacity"

  test "optional component initializers reject policies without that component":
    let policy = apiAbuseProtectionPolicy()

    expect FlowPolicyConfigError:
      discard initBudgetLedger(policy)
    expect FlowPolicyConfigError:
      discard initCircuitBreaker(policy)
    expect FlowPolicyConfigError:
      discard initBulkhead(policy)

  test "policy constructors reject invalid inputs":
    expect FlowPolicyConfigError:
      discard apiAbuseProtectionPolicy(name = " ")
    expect FlowPolicyConfigError:
      discard workerBackpressurePolicy(concurrency = 0)
