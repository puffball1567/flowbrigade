import std/unittest

import flowbrigade/ratelimit
import flowbrigade_ready

suite "ready bridge":
  test "reports inherited adapter capabilities":
    let capabilities = readyRateLimitCapabilities()

    check capabilities.supports(rlcInspect)
    check capabilities.supports(rlcAtomicConsume)
    check capabilities.supports(rlcDistributed)
    check not capabilities.supports(rlcReservation)

  test "rejects nil ready connections":
    expect RateLimitConfigError:
      discard readyCommandProc(nil)

    expect RateLimitConfigError:
      discard initReadyRateLimitStorage(nil)
