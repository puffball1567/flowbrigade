import std/strutils

import flowbrigade

var primaryCalls = 0
var fallbackCalls = 0

proc primarySearch(): string =
  inc primaryCalls
  raise newException(IOError, "primary search is temporarily unavailable")

proc cachedSearch(): string =
  inc fallbackCalls
  "cached result"

let result = fallback(
  primary = primarySearch,
  secondary = cachedSearch,
  shouldFallback = proc(error: ref CatchableError): bool =
    error.msg.contains("temporarily")
)

doAssert result == "cached result"
doAssert primaryCalls == 1
doAssert fallbackCalls == 1

var breaker = initCircuitBreaker(failureThreshold = 1, resetAfter = 30.sec)
breaker.recordFailure()

let routed = tryInOrder([
  fallbackProvider("primary", breaker, proc(): string =
    "should not run while the circuit is open"
  ),
  fallbackProvider("secondary", proc(): string =
    "secondary result"
  )
])

doAssert routed.provider == "secondary"
doAssert routed.value == "secondary result"
