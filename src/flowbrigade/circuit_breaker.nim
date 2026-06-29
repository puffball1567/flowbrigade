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
    observer: CircuitBreakerObserverProc = nil
): CircuitBreaker =
  if failureThreshold <= 0:
    raise newException(CircuitBreakerConfigError, "failureThreshold must be positive")
  if resetAfter <= initDuration():
    raise newException(CircuitBreakerConfigError, "resetAfter must be positive")
  CircuitBreaker(
    failureThreshold: failureThreshold,
    resetAfter: resetAfter,
    currentState: circuitClosed,
    timeSource: timeSource,
    observer: observer
  )

proc initCircuitBreaker*(
    failureThreshold: int;
    resetAfter: Duration;
    observer: CircuitBreakerObserverProc = nil
): CircuitBreaker =
  initCircuitBreaker(
    failureThreshold = failureThreshold,
    resetAfter = resetAfter,
    timeSource = initTimeSource(),
    observer = observer
  )

proc state*(breaker: CircuitBreaker): CircuitState =
  breaker.currentState

proc allow*(breaker: var CircuitBreaker): bool =
  case breaker.currentState
  of circuitClosed, circuitHalfOpen:
    breaker.emit(circuitAllowed)
    true
  of circuitOpen:
    if breaker.timeSource.now() - breaker.openedAt >= breaker.resetAfter:
      breaker.currentState = circuitHalfOpen
      breaker.emit(circuitHalfOpened)
      breaker.emit(circuitAllowed)
      return true
    breaker.emit(circuitBlocked)
    false

proc recordSuccess*(breaker: var CircuitBreaker) =
  breaker.failures = 0
  breaker.currentState = circuitClosed
  breaker.openedAt = initDuration()
  breaker.emit(circuitClosedAfterSuccess)

proc recordFailure*(breaker: var CircuitBreaker) =
  case breaker.currentState
  of circuitHalfOpen:
    breaker.currentState = circuitOpen
    breaker.openedAt = breaker.timeSource.now()
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
