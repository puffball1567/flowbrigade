import std/[times, unittest]

import flowbrigade/circuit_breaker
import flowbrigade/internal/time_source

suite "circuit breaker":
  test "starts closed and allows calls":
    let time = initManualTimeSource()
    var breaker = initCircuitBreaker(
      failureThreshold = 2,
      resetAfter = initDuration(seconds = 5),
      timeSource = time
    )

    check breaker.state() == circuitClosed
    check breaker.allow()

  test "opens after consecutive failures reach the threshold":
    let time = initManualTimeSource()
    var breaker = initCircuitBreaker(
      failureThreshold = 2,
      resetAfter = initDuration(seconds = 5),
      timeSource = time
    )

    breaker.recordFailure()
    check breaker.state() == circuitClosed
    check breaker.allow()

    breaker.recordFailure()
    check breaker.state() == circuitOpen
    check not breaker.allow()

  test "moves to half open after reset delay":
    let time = initManualTimeSource()
    var breaker = initCircuitBreaker(
      failureThreshold = 1,
      resetAfter = initDuration(seconds = 5),
      timeSource = time
    )

    breaker.recordFailure()
    time.advance(initDuration(milliseconds = 4999))
    check not breaker.allow()

    time.advance(initDuration(milliseconds = 1))
    check breaker.allow()
    check breaker.state() == circuitHalfOpen

  test "success in half open closes the circuit":
    let time = initManualTimeSource()
    var breaker = initCircuitBreaker(
      failureThreshold = 1,
      resetAfter = initDuration(seconds = 5),
      timeSource = time
    )

    breaker.recordFailure()
    time.advance(initDuration(seconds = 5))
    check breaker.allow()

    breaker.recordSuccess()
    check breaker.state() == circuitClosed
    check breaker.allow()

  test "failure in half open reopens the circuit":
    let time = initManualTimeSource()
    var breaker = initCircuitBreaker(
      failureThreshold = 1,
      resetAfter = initDuration(seconds = 5),
      timeSource = time
    )

    breaker.recordFailure()
    time.advance(initDuration(seconds = 5))
    check breaker.allow()

    breaker.recordFailure()
    check breaker.state() == circuitOpen
    check not breaker.allow()

  test "rejects invalid circuit breaker configuration":
    let time = initManualTimeSource()

    expect CircuitBreakerConfigError:
      discard initCircuitBreaker(
        failureThreshold = 0,
        resetAfter = initDuration(seconds = 1),
        timeSource = time
      )

    expect CircuitBreakerConfigError:
      discard initCircuitBreaker(
        failureThreshold = 1,
        resetAfter = initDuration(),
        timeSource = time
      )

  test "default constructor uses a real time source":
    var breaker = initCircuitBreaker(
      failureThreshold = 1,
      resetAfter = initDuration(seconds = 1)
    )

    check breaker.allow()

  test "observer receives state and decision events":
    let time = initManualTimeSource()
    var events: seq[CircuitBreakerEventKind] = @[]

    proc observe(event: CircuitBreakerEvent) =
      events.add(event.kind)

    var breaker = initCircuitBreaker(
      failureThreshold = 1,
      resetAfter = initDuration(seconds = 1),
      timeSource = time,
      observer = observe
    )

    check breaker.allow()
    breaker.recordFailure()
    check not breaker.allow()
    time.advance(initDuration(seconds = 1))
    check breaker.allow()
    breaker.recordSuccess()

    check events == @[
      circuitAllowed,
      circuitOpened,
      circuitBlocked,
      circuitHalfOpened,
      circuitAllowed,
      circuitClosedAfterSuccess
    ]
