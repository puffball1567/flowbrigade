import std/[asyncdispatch, strutils, unittest]

import flowbrigade

suite "async fallback":
  test "returns primary result when it succeeds":
    var primaryCalls = 0
    var secondaryCalls = 0

    proc primary(): Future[string] {.async.} =
      inc primaryCalls
      return "primary"

    proc secondary(): Future[string] {.async.} =
      inc secondaryCalls
      return "secondary"

    let value = waitFor fallbackAsync(primary, secondary)

    check value == "primary"
    check primaryCalls == 1
    check secondaryCalls == 0

  test "uses secondary when primary future fails":
    proc primary(): Future[string] {.async.} =
      raise newException(IOError, "primary failed")

    proc secondary(): Future[string] {.async.} =
      return "secondary"

    let value = waitFor fallbackAsync(primary, secondary)

    check value == "secondary"

  test "tryInOrderAsync returns provider metadata":
    proc first(): Future[string] {.async.} =
      raise newException(IOError, "first failed")

    proc second(): Future[string] {.async.} =
      return "ok"

    let result = waitFor tryInOrderAsync([
      asyncFallbackProvider("first", first),
      asyncFallbackProvider("second", second)
    ])

    check result.value == "ok"
    check result.provider == "second"
    check result.attempts == 2
    check result.failedProviders == @["first"]
    check result.lastError == "first failed"

  test "raises typed fallback error when every async provider fails":
    proc first(): Future[string] {.async.} =
      raise newException(IOError, "first failed")

    proc second(): Future[string] {.async.} =
      raise newException(IOError, "second failed")

    expect FallbackError:
      discard waitFor tryInOrderAsync([
        asyncFallbackProvider("first", first),
        asyncFallbackProvider("second", second)
      ])

  test "predicate can stop async fallback":
    proc shouldFallback(error: ref CatchableError): bool =
      not error.msg.contains("fatal")

    proc primary(): Future[string] {.async.} =
      raise newException(IOError, "fatal failure")

    proc secondary(): Future[string] {.async.} =
      return "secondary"

    expect IOError:
      discard waitFor fallbackAsync(
        primary,
        secondary,
        shouldFallback = shouldFallback
      )

  test "observer receives async attempt failure and success events":
    var events: seq[FallbackEventKind] = @[]

    proc first(): Future[int] {.async.} =
      raise newException(IOError, "first failed")

    proc second(): Future[int] {.async.} =
      return 42

    let result = waitFor tryInOrderAsync([
      asyncFallbackProvider("first", first),
      asyncFallbackProvider("second", second)
    ], observer = proc(event: FallbackEvent) =
      events.add(event.kind)
    )

    check result.value == 42
    check events == @[
      fallbackAttempt,
      fallbackFailed,
      fallbackAttempt,
      fallbackSucceeded
    ]

  test "open circuit breaker skips async provider":
    var breaker = initCircuitBreaker(failureThreshold = 1, resetAfter = 1.hr)
    breaker.recordFailure()
    var primaryCalls = 0

    proc primary(): Future[string] {.async.} =
      inc primaryCalls
      return "primary"

    proc secondary(): Future[string] {.async.} =
      return "secondary"

    let result = waitFor tryInOrderAsync([
      asyncFallbackProvider("primary", breaker, primary),
      asyncFallbackProvider("secondary", secondary)
    ])

    check result.value == "secondary"
    check result.provider == "secondary"
    check primaryCalls == 0
    check result.failedProviders == @["primary"]

  test "async provider with circuit breaker records failure":
    var breaker = initCircuitBreaker(failureThreshold = 1, resetAfter = 1.hr)

    proc primary(): Future[string] {.async.} =
      raise newException(IOError, "primary failed")

    proc secondary(): Future[string] {.async.} =
      return "secondary"

    let result = waitFor tryInOrderAsync([
      asyncFallbackProvider("primary", breaker, primary),
      asyncFallbackProvider("secondary", secondary)
    ])

    check result.value == "secondary"
    check breaker.state == circuitOpen

  test "rejects invalid async fallback configuration":
    var nilProvider: proc(): Future[string] {.closure.} = nil

    expect FallbackConfigError:
      discard waitFor tryInOrderAsync(newSeq[AsyncFallbackProvider[string]]())
    expect FallbackConfigError:
      discard asyncFallbackProvider(" ", proc(): Future[string] {.async.} =
        return "ok"
      )
    expect FallbackConfigError:
      discard asyncFallbackProvider("x", nilProvider)
