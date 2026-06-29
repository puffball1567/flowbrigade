import flowbrigade

var throttle = initThrottle(every = 100.ms)
var breaker = initCircuitBreaker(failureThreshold = 2, resetAfter = 1.sec)
let deadline = initTimeout(after = 5.sec)

if throttle.allow() and breaker.allow() and not deadline.expired():
  try:
    raise newException(IOError, "downstream failed")
  except IOError:
    breaker.recordFailure()

doAssert not deadline.expired()
doAssert breaker.state == circuitClosed

breaker.recordFailure()
doAssert breaker.state == circuitOpen
