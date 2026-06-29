import flowbrigade

var throughput = initTokenBucket(rate = 10, per = 1.sec, burst = 20)
var breaker = initCircuitBreaker(failureThreshold = 3, resetAfter = 30.sec)
let deadline = initTimeout(after = 5.sec)

proc runJob(): bool =
  throughput.allow() and breaker.allow() and not deadline.expired()

if runJob():
  breaker.recordSuccess()

doAssert breaker.state == circuitClosed
