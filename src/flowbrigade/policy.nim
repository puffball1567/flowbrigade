import std/[strutils, times]

import ./budget
import ./bulkhead
import ./circuit_breaker
import ./config
import ./durations
import ./presets
import ./ratelimit

type
  FlowPolicyConfigError* = object of ValueError

  FlowPolicyValidationIssueKind* = enum
    fpviMissingPrimaryLimiter,
    fpviMissingLimiter,
    fpviInvalidQuota,
    fpviInvalidRetry,
    fpviInvalidCircuitBreaker,
    fpviInvalidBulkhead

  FlowPolicyKind* = enum
    fpkApiAbuseProtection,
    fpkLoginProtection,
    fpkPasswordResetProtection,
    fpkThirdPartyApiClient,
    fpkWorkerBackpressure,
    fpkMultiTenantQuota

  FlowPolicy* = object
    kind*: FlowPolicyKind
    name*: string
    registry*: LimiterRegistry
    primaryLimiter*: string
    quota*: BudgetConfig
    retry*: RetryConfig
    circuitBreaker*: CircuitBreakerConfig
    bulkheadCapacity*: int

  FlowPolicyValidationIssue* = object
    kind*: FlowPolicyValidationIssueKind
    path*: string
    message*: string

  FlowPolicyValidationReport* = object
    valid*: bool
    policyName*: string
    limiterCount*: int
    hasQuota*: bool
    hasRetry*: bool
    hasCircuitBreaker*: bool
    hasBulkhead*: bool
    issues*: seq[FlowPolicyValidationIssue]

  FlowPolicyRequirement* = enum
    fprQuota,
    fprRetry,
    fprCircuitBreaker,
    fprBulkhead

proc requireName(name: string): string =
  result = name.strip()
  if result.len == 0:
    raise newException(FlowPolicyConfigError, "policy name must not be empty")

proc addIfMissing(
    registry: var LimiterRegistry;
    name: string;
    handle: LimiterHandle
) =
  if not registry.hasLimiter(name):
    registry.addLimiter(name, handle)

proc initFlowPolicy*(
    kind: FlowPolicyKind;
    name: string;
    primaryLimiter: string;
    registry: LimiterRegistry;
    quota: BudgetConfig = BudgetConfig();
    retry: RetryConfig = RetryConfig();
    circuitBreaker: CircuitBreakerConfig = CircuitBreakerConfig();
    bulkheadCapacity = 0
): FlowPolicy =
  if primaryLimiter.strip().len == 0:
    raise newException(FlowPolicyConfigError, "primary limiter must not be empty")
  FlowPolicy(
    kind: kind,
    name: requireName(name),
    registry: registry,
    primaryLimiter: primaryLimiter,
    quota: quota,
    retry: retry,
    circuitBreaker: circuitBreaker,
    bulkheadCapacity: bulkheadCapacity
  )

proc addIssue(
    report: var FlowPolicyValidationReport;
    kind: FlowPolicyValidationIssueKind;
    path, message: string
) =
  report.issues.add(FlowPolicyValidationIssue(kind: kind, path: path, message: message))
  report.valid = false

proc validate*(policy: FlowPolicy): FlowPolicyValidationReport =
  ## Returns a non-throwing validation report for a composed policy.
  ##
  ## This is intended for configuration loading, startup checks, and dry-run
  ## tooling. It does not consume limiter state.
  result = FlowPolicyValidationReport(
    valid: true,
    policyName: policy.name,
    limiterCount: policy.registry.limiterNames.len,
    hasQuota: policy.quota.limit > 0,
    hasRetry: policy.retry.maxAttempts > 0,
    hasCircuitBreaker: policy.circuitBreaker.failureThreshold > 0,
    hasBulkhead: policy.bulkheadCapacity > 0
  )

  if policy.primaryLimiter.strip().len == 0:
    result.addIssue(
      fpviMissingPrimaryLimiter,
      "primaryLimiter",
      "primary limiter must not be empty"
    )
  elif not policy.registry.hasLimiter(policy.primaryLimiter):
    result.addIssue(
      fpviMissingLimiter,
      "primaryLimiter",
      "primary limiter is not registered"
    )

  if policy.quota.limit < 0 or policy.quota.per < initDuration():
    result.addIssue(fpviInvalidQuota, "quota", "quota values must be positive when configured")
  if policy.retry.maxAttempts < 0:
    result.addIssue(fpviInvalidRetry, "retry", "retry max attempts must not be negative")
  if policy.circuitBreaker.failureThreshold < 0 or policy.circuitBreaker.resetAfter < initDuration():
    result.addIssue(
      fpviInvalidCircuitBreaker,
      "circuitBreaker",
      "circuit breaker values must be positive when configured"
    )
  if policy.bulkheadCapacity < 0:
    result.addIssue(fpviInvalidBulkhead, "bulkheadCapacity", "bulkhead capacity must not be negative")

proc requireValid*(policy: FlowPolicy): FlowPolicyValidationReport =
  ## Validates a policy and raises `FlowPolicyConfigError` when it is not usable.
  result = policy.validate()
  if not result.valid:
    raise newException(FlowPolicyConfigError, result.issues[0].message)

proc require*(policy: FlowPolicy; requirements: openArray[FlowPolicyRequirement]): FlowPolicyValidationReport =
  ## Validates that optional policy parts needed by an application are present.
  result = policy.validate()
  for requirement in requirements:
    case requirement
    of fprQuota:
      if not result.hasQuota:
        result.addIssue(fpviInvalidQuota, "quota", "policy does not include a quota")
    of fprRetry:
      if not result.hasRetry:
        result.addIssue(fpviInvalidRetry, "retry", "policy does not include retry config")
    of fprCircuitBreaker:
      if not result.hasCircuitBreaker:
        result.addIssue(
          fpviInvalidCircuitBreaker,
          "circuitBreaker",
          "policy does not include a circuit breaker"
        )
    of fprBulkhead:
      if not result.hasBulkhead:
        result.addIssue(fpviInvalidBulkhead, "bulkheadCapacity", "policy does not include a bulkhead")
  if not result.valid:
    raise newException(FlowPolicyConfigError, result.issues[0].message)

proc apiAbuseProtectionPolicy*(
    name = "api_abuse";
    perIdentityLimit = 120;
    perIdentityWindow = 1.min;
    globalRate = 1000;
    globalPer = 1.sec;
    globalBurst = 2000
): FlowPolicy =
  let policyName = requireName(name)
  var registry = initLimiterRegistry()
  registry.addLimiter(
    policyName & "_identity",
    keyedFixedWindowDefinition(limit = perIdentityLimit, per = perIdentityWindow)
  )
  registry.addLimiter(
    policyName & "_global",
    tokenBucketDefinition(rate = globalRate, per = globalPer, burst = globalBurst)
  )
  registry.addCompoundLimiter(policyName, [policyName & "_identity", policyName & "_global"])
  initFlowPolicy(
    kind = fpkApiAbuseProtection,
    name = policyName,
    primaryLimiter = policyName,
    registry = registry
  )

proc loginProtectionPolicy*(
    name = "login_guard";
    accountLimit = 5;
    accountWindow = 15.min;
    identityLimit = 20;
    identityWindow = 1.hr
): FlowPolicy =
  let policyName = requireName(name)
  var registry = initLimiterRegistry()
  registry.addLimiter(
    policyName & "_account",
    keyedFixedWindowDefinition(limit = accountLimit, per = accountWindow)
  )
  registry.addLimiter(
    policyName & "_identity",
    keyedFixedWindowDefinition(limit = identityLimit, per = identityWindow)
  )
  registry.addCompoundLimiter(policyName, [policyName & "_account", policyName & "_identity"])
  initFlowPolicy(
    kind = fpkLoginProtection,
    name = policyName,
    primaryLimiter = policyName,
    registry = registry
  )

proc passwordResetProtectionPolicy*(
    name = "password_reset";
    accountLimit = 3;
    accountWindow = 1.hr;
    identityLimit = 10;
    identityWindow = 1.hr
): FlowPolicy =
  let policyName = requireName(name)
  var registry = initLimiterRegistry()
  registry.addLimiter(
    policyName & "_account",
    keyedFixedWindowDefinition(limit = accountLimit, per = accountWindow)
  )
  registry.addLimiter(
    policyName & "_identity",
    keyedFixedWindowDefinition(limit = identityLimit, per = identityWindow)
  )
  registry.addCompoundLimiter(policyName, [policyName & "_account", policyName & "_identity"])
  initFlowPolicy(
    kind = fpkPasswordResetProtection,
    name = policyName,
    primaryLimiter = policyName,
    registry = registry
  )

proc thirdPartyApiClientPolicy*(
    name = "third_party_api";
    rate = 10;
    per = 1.sec;
    burst = 20;
    failureThreshold = 3;
    resetAfter = 30.sec
): FlowPolicy =
  let policyName = requireName(name)
  var registry = initLimiterRegistry()
  registry.addLimiter(
    policyName,
    tokenBucketDefinition(rate = rate, per = per, burst = burst)
  )
  initFlowPolicy(
    kind = fpkThirdPartyApiClient,
    name = policyName,
    primaryLimiter = policyName,
    registry = registry,
    retry = apiClientRetryConfig(),
    circuitBreaker = strictCircuitBreakerConfig(
      failureThreshold = failureThreshold,
      resetAfter = resetAfter
    )
  )

proc workerBackpressurePolicy*(
    name = "worker_backpressure";
    rate = 10;
    per = 1.sec;
    burst = 20;
    concurrency = 4;
    failureThreshold = 3;
    resetAfter = 30.sec
): FlowPolicy =
  let policyName = requireName(name)
  if concurrency <= 0:
    raise newException(FlowPolicyConfigError, "concurrency must be positive")
  var registry = initLimiterRegistry()
  registry.addLimiter(
    policyName,
    tokenBucketDefinition(rate = rate, per = per, burst = burst)
  )
  initFlowPolicy(
    kind = fpkWorkerBackpressure,
    name = policyName,
    primaryLimiter = policyName,
    registry = registry,
    retry = workerRetryConfig(),
    circuitBreaker = strictCircuitBreakerConfig(
      failureThreshold = failureThreshold,
      resetAfter = resetAfter
    ),
    bulkheadCapacity = concurrency
  )

proc multiTenantQuotaPolicy*(
    name = "tenant_quota";
    quotaLimit: int64 = 100_000;
    quotaPeriod = 30.day;
    burstLimit = 100;
    burstWindow = 1.min
): FlowPolicy =
  let policyName = requireName(name)
  var registry = initLimiterRegistry()
  registry.addLimiter(
    policyName & "_burst",
    keyedFixedWindowDefinition(limit = burstLimit, per = burstWindow)
  )
  initFlowPolicy(
    kind = fpkMultiTenantQuota,
    name = policyName,
    primaryLimiter = policyName & "_burst",
    registry = registry,
    quota = initBudgetConfig(limit = quotaLimit, per = quotaPeriod)
  )

proc consume*(policy: FlowPolicy; key: string; cost = 1): RateLimitResult =
  policy.registry.consume(policy.primaryLimiter, key = key, cost = cost)

proc inspect*(policy: FlowPolicy; key: string; cost = 1): RateLimitResult =
  policy.registry.inspect(policy.primaryLimiter, key = key, cost = cost)

proc allow*(policy: FlowPolicy; key: string; cost = 1): bool =
  policy.consume(key, cost).allowed

proc initBudgetLedger*(policy: FlowPolicy): BudgetLedger =
  if policy.quota.limit <= 0:
    raise newException(FlowPolicyConfigError, "policy does not include a quota")
  initBudgetLedger(policy.quota)

proc initCircuitBreaker*(policy: FlowPolicy): CircuitBreaker =
  if policy.circuitBreaker.failureThreshold <= 0:
    raise newException(FlowPolicyConfigError, "policy does not include a circuit breaker")
  initCircuitBreaker(policy.circuitBreaker)

proc initBulkhead*(policy: FlowPolicy): Bulkhead =
  if policy.bulkheadCapacity <= 0:
    raise newException(FlowPolicyConfigError, "policy does not include a bulkhead")
  initBulkhead(policy.bulkheadCapacity)

proc mergeInto*(policy: FlowPolicy; registry: var LimiterRegistry) =
  for limiterName in policy.registry.limiterNames:
    let source = policy.registry
    let copiedName = $limiterName
    registry.addIfMissing(copiedName, LimiterHandle(
      inspect: proc(key: string; cost: int): RateLimitResult =
        source.inspect(copiedName, key, cost),
      consume: proc(key: string; cost: int): RateLimitResult =
        source.consume(copiedName, key, cost),
      clear: proc(key: string): bool =
        source.clear(copiedName, key)
    ))
