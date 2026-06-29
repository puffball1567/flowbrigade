import flowbrigade

let login = loginProtectionPolicy(accountLimit = 2, accountWindow = 1.min)

doAssert login.allow("account:42")
doAssert login.allow("account:42")
doAssert not login.allow("account:42")

let apiClient = thirdPartyApiClientPolicy(rate = 1, per = 1.sec, burst = 1)

doAssert apiClient.allow("vendor:search")
doAssert not apiClient.allow("vendor:search")

var breaker = initCircuitBreaker(apiClient)
doAssert breaker.allow()
breaker.recordFailure()
breaker.recordFailure()
breaker.recordFailure()
doAssert not breaker.allow()

let worker = workerBackpressurePolicy(rate = 2, per = 1.sec, burst = 2, concurrency = 1)
var bulkhead = initBulkhead(worker)

doAssert bulkhead.tryAcquire()
doAssert not bulkhead.tryAcquire()
