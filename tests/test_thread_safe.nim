import std/unittest

import flowbrigade

suite "thread-safe wrappers":
  test "thread-safe policy serializes in-memory policy access":
    let policy = initThreadSafeFlowPolicy(apiAbuseProtectionPolicy(
      perIdentityLimit = 1,
      perIdentityWindow = 1.min,
      globalRate = 10,
      globalPer = 1.sec,
      globalBurst = 10
    ))

    check policy.consume("client:1").allowed
    check not policy.consume("client:1").allowed
    check policy.consume("client:2").allowed

  test "thread-safe registry serializes named limiter access":
    var registry = initLimiterRegistry()
    registry.addLimiter("api", keyedFixedWindowDefinition(limit = 1, per = 1.min))
    let safeRegistry = initThreadSafeLimiterRegistry(registry)

    check safeRegistry.consume("api", "client:1").allowed
    check not safeRegistry.consume("api", "client:1").allowed
    check safeRegistry.consume("api", "client:2").allowed

  test "thread-safe wrappers reject nil handles":
    expect FlowPolicyConfigError:
      discard ThreadSafeFlowPolicy(nil).consume("client:1")
    expect RateLimitConfigError:
      discard ThreadSafeLimiterRegistry(nil).consume("api", "client:1")
