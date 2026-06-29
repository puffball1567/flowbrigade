import std/[strutils, unittest]

import flowbrigade

suite "fallback":
  test "returns primary result when it succeeds":
    var primaryCalls = 0
    var secondaryCalls = 0

    let value = fallback(
      primary = proc(): string =
        inc primaryCalls
        "primary",
      secondary = proc(): string =
        inc secondaryCalls
        "secondary"
    )

    check value == "primary"
    check primaryCalls == 1
    check secondaryCalls == 0

  test "uses secondary when primary fails":
    let value = fallback(
      primary = proc(): string =
        raise newException(IOError, "primary failed"),
      secondary = proc(): string =
        "secondary"
    )

    check value == "secondary"

  test "tryInOrder returns provider metadata":
    let result = tryInOrder([
      fallbackProvider("a", proc(): string =
        raise newException(IOError, "a failed")
      ),
      fallbackProvider("b", proc(): string =
        "ok"
      )
    ])

    check result.value == "ok"
    check result.provider == "b"
    check result.attempts == 2
    check result.failedProviders == @["a"]
    check result.lastError == "a failed"

  test "raises typed fallback error when every provider fails":
    expect FallbackError:
      discard tryInOrder([
        fallbackProvider("a", proc(): string =
          raise newException(IOError, "a failed")
        ),
        fallbackProvider("b", proc(): string =
          raise newException(IOError, "b failed")
        )
      ])

  test "predicate can stop fallback":
    proc shouldFallback(error: ref CatchableError): bool =
      not error.msg.contains("fatal")

    expect IOError:
      discard fallback(
        primary = proc(): string =
          raise newException(IOError, "fatal failure"),
        secondary = proc(): string =
          "secondary",
        shouldFallback = shouldFallback
      )

  test "observer receives attempt failure and success events":
    var events: seq[FallbackEventKind] = @[]

    let result = tryInOrder([
      fallbackProvider("a", proc(): int =
        raise newException(IOError, "a failed")
      ),
      fallbackProvider("b", proc(): int =
        42
      )
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

  test "open circuit breaker skips a provider":
    var breaker = initCircuitBreaker(failureThreshold = 1, resetAfter = 1.hr)
    breaker.recordFailure()
    var primaryCalls = 0

    let result = tryInOrder([
      fallbackProvider("primary", breaker, proc(): string =
        inc primaryCalls
        "primary"
      ),
      fallbackProvider("secondary", proc(): string =
        "secondary"
      )
    ])

    check result.value == "secondary"
    check result.provider == "secondary"
    check primaryCalls == 0
    check result.failedProviders == @["primary"]

  test "provider with circuit breaker records failure and success":
    var breaker = initCircuitBreaker(failureThreshold = 1, resetAfter = 1.hr)

    let result = tryInOrder([
      fallbackProvider("primary", breaker, proc(): string =
        raise newException(IOError, "primary failed")
      ),
      fallbackProvider("secondary", proc(): string =
        "secondary"
      )
    ])

    check result.value == "secondary"
    check breaker.state == circuitOpen

  test "rejects invalid fallback configuration":
    var nilProvider: proc(): string {.closure.} = nil

    expect FallbackConfigError:
      discard tryInOrder(newSeq[FallbackProvider[string]]())
    expect FallbackConfigError:
      discard fallbackProvider(" ", proc(): string = "ok")
    expect FallbackConfigError:
      discard fallbackProvider("x", nilProvider)
