import std/times
import flowbrigade

proc main() =
  var allowed = 0
  for i in 0 ..< 1000:
    var bucket = initTokenBucket(rate = 25, per = initDuration(seconds = 1), burst = 50)
    if bucket.allow(cost = 2):
      inc allowed

    var keyed = initKeyedFixedWindow[string](
      limit = 3,
      per = initDuration(seconds = 1),
      maxKeys = 128
    )
    discard keyed.allow("tenant-" & $i)
    discard keyed.clear("tenant-" & $i)

    var breaker = initCircuitBreaker(
      failureThreshold = 3,
      resetAfter = initDuration(seconds = 1)
    )
    discard breaker.allow()
    breaker.recordFailure()
    breaker.recordSuccess()

    var ledger = initBudgetLedger(limit = 10, per = initDuration(seconds = 1))
    discard ledger.consume("tenant-" & $i, 1)
    discard ledger.refund("tenant-" & $i, 1)

  doAssert allowed == 1000

main()
