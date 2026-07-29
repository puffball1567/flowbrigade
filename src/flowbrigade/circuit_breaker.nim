import std/times

import ./internal/time_source

type
  CircuitBreakerConfigError* = object of ValueError

  CircuitState* = enum
    circuitClosed, circuitOpen, circuitHalfOpen

  CircuitBreakerEventKind* = enum
    circuitAllowed, circuitBlocked, circuitOpened, circuitHalfOpened, circuitClosedAfterSuccess

  CircuitBreakerEvent* = object
    kind*: CircuitBreakerEventKind
    state*: CircuitState
    failures*: int

  CircuitBreakerObserverProc* = proc(event: CircuitBreakerEvent) {.closure.}

  CircuitBreaker* = object
    failureThreshold: int
    resetAfter: Duration
    failures: int
    currentState: CircuitState
    openedAt: Duration
    halfOpenProbes: int
    halfOpenMaxProbes: int
    timeSource: TimeSource
    observer: CircuitBreakerObserverProc

proc emit(breaker: CircuitBreaker; kind: CircuitBreakerEventKind) =
  if not breaker.observer.isNil:
    breaker.observer(CircuitBreakerEvent(
      kind: kind,
      state: breaker.currentState,
      failures: breaker.failures
    ))

proc initCircuitBreaker*(
    failureThreshold: int;
    resetAfter: Duration;
    timeSource: TimeSource;
    observer: CircuitBreakerObserverProc = nil;
    halfOpenMaxProbes = 1
): CircuitBreaker =
  if failureThreshold <= 0:
    raise newException(CircuitBreakerConfigError, "failureThreshold must be positive")
  if resetAfter <= initDuration():
    raise newException(CircuitBreakerConfigError, "resetAfter must be positive")
  if halfOpenMaxProbes <= 0:
    raise newException(CircuitBreakerConfigError, "halfOpenMaxProbes must be positive")
  CircuitBreaker(
    failureThreshold: failureThreshold,
    resetAfter: resetAfter,
    halfOpenMaxProbes: halfOpenMaxProbes,
    currentState: circuitClosed,
    timeSource: timeSource,
    observer: observer
  )

proc initCircuitBreaker*(
    failureThreshold: int;
    resetAfter: Duration;
    observer: CircuitBreakerObserverProc = nil;
    halfOpenMaxProbes = 1
): CircuitBreaker =
  initCircuitBreaker(
    failureThreshold = failureThreshold,
    resetAfter = resetAfter,
    timeSource = initTimeSource(),
    observer = observer,
    halfOpenMaxProbes = halfOpenMaxProbes
  )

proc state*(breaker: CircuitBreaker): CircuitState =
  breaker.currentState

proc allow*(breaker: var CircuitBreaker): bool =
  case breaker.currentState
  of circuitClosed:
    breaker.emit(circuitAllowed)
    true
  of circuitHalfOpen:
    if breaker.halfOpenProbes >= breaker.halfOpenMaxProbes:
      breaker.emit(circuitBlocked)
      return false
    inc breaker.halfOpenProbes
    breaker.emit(circuitAllowed)
    true
  of circuitOpen:
    if breaker.timeSource.now() - breaker.openedAt >= breaker.resetAfter:
      breaker.currentState = circuitHalfOpen
      breaker.halfOpenProbes = 1
      breaker.emit(circuitHalfOpened)
      breaker.emit(circuitAllowed)
      return true
    breaker.emit(circuitBlocked)
    false

proc recordSuccess*(breaker: var CircuitBreaker) =
  breaker.failures = 0
  breaker.currentState = circuitClosed
  breaker.openedAt = initDuration()
  breaker.halfOpenProbes = 0
  breaker.emit(circuitClosedAfterSuccess)

proc recordFailure*(breaker: var CircuitBreaker) =
  case breaker.currentState
  of circuitHalfOpen:
    breaker.currentState = circuitOpen
    breaker.openedAt = breaker.timeSource.now()
    breaker.halfOpenProbes = 0
    breaker.failures = breaker.failureThreshold
    breaker.emit(circuitOpened)
  of circuitOpen:
    breaker.openedAt = breaker.timeSource.now()
  of circuitClosed:
    inc breaker.failures
    if breaker.failures >= breaker.failureThreshold:
      breaker.currentState = circuitOpen
      breaker.openedAt = breaker.timeSource.now()
      breaker.emit(circuitOpened)
