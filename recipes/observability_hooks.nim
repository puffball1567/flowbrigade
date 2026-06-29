import std/times

import flowbrigade

var retryEvents: seq[RetryEventKind] = @[]
var attempts = 0

let retryResult = retry(
  policy = fixedBackoff(10.ms),
  maxAttempts = 2,
  sleep = proc(delay: Duration) = discard,
  operation = proc(): string =
    inc attempts
    if attempts == 1:
      raise newException(IOError, "temporary")
    "ok",
  observer = proc(event: RetryEvent) =
    retryEvents.add(event.kind)
)

doAssert retryResult == "ok"
doAssert retryEvents == @[retryAttemptFailed, retrySleeping, retrySucceeded]

var circuitEvents: seq[CircuitBreakerEventKind] = @[]
var breaker = initCircuitBreaker(
  failureThreshold = 1,
  resetAfter = 1.sec,
  observer = proc(event: CircuitBreakerEvent) =
    circuitEvents.add(event.kind)
)

doAssert breaker.allow()
breaker.recordFailure()
doAssert not breaker.allow()
doAssert circuitEvents == @[circuitAllowed, circuitOpened, circuitBlocked]

var auditEvents: seq[StoredFixedWindowAction] = @[]
let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
let limiter = initStoredFixedWindow(
  prefix = "api",
  limit = 2,
  per = 1.min,
  storage = storage,
  audit = proc(event: StoredFixedWindowAuditEvent) =
    auditEvents.add(event.action)
)

discard limiter.inspect("user:42")
discard limiter.consume("user:42")
discard limiter.clear("user:42")

doAssert auditEvents == @[sfwaInspect, sfwaConsume, sfwaClear]
