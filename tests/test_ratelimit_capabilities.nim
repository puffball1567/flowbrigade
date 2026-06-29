import std/unittest

import flowbrigade/ratelimit

suite "rate limit adapter capabilities":
  test "builds capability sets":
    let capabilities = initRateLimitCapabilities([rlcInspect, rlcAtomicConsume])

    check capabilities.supports(rlcInspect)
    check capabilities.supports(rlcAtomicConsume)
    check not capabilities.supports(rlcReservation)

  test "requires single capabilities":
    let capabilities = initRateLimitCapabilities([rlcInspect])

    capabilities.requireCapability(rlcInspect)

    expect RateLimitConfigError:
      capabilities.requireCapability(rlcAtomicConsume)

  test "requires multiple capabilities":
    let capabilities = distributedFixedWindowCapabilities()

    capabilities.requireCapabilities([rlcInspect, rlcAtomicConsume, rlcDistributed])

    expect RateLimitConfigError:
      capabilities.requireCapabilities([rlcReservation])

  test "predefined capability sets describe expected support":
    let memory = inMemoryRateLimitCapabilities()
    let distributed = distributedFixedWindowCapabilities()

    check memory.supports(rlcClear)
    check not memory.supports(rlcDistributed)
    check distributed.supports(rlcDistributed)
    check distributed.supports(rlcAtomicConsume)
