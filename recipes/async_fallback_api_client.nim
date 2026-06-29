import std/[asyncdispatch, strutils]

import flowbrigade

proc primarySearch(): Future[string] {.async.} =
  raise newException(IOError, "primary search is temporarily unavailable")

proc cachedSearch(): Future[string] {.async.} =
  return "cached result"

let value = waitFor fallbackAsync(
  primary = primarySearch,
  secondary = cachedSearch,
  shouldFallback = proc(error: ref CatchableError): bool =
    error.msg.contains("temporarily")
)

doAssert value == "cached result"

var breaker = initCircuitBreaker(failureThreshold = 1, resetAfter = 30.sec)
breaker.recordFailure()

proc skippedPrimary(): Future[string] {.async.} =
  return "should not run while the circuit is open"

proc secondary(): Future[string] {.async.} =
  return "secondary result"

let routed = waitFor tryInOrderAsync([
  asyncFallbackProvider("primary", breaker, skippedPrimary),
  asyncFallbackProvider("secondary", secondary)
])

doAssert routed.provider == "secondary"
doAssert routed.value == "secondary result"
