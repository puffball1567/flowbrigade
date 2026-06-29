type
  BulkheadConfigError* = object of ValueError
  BulkheadError* = object of CatchableError

  BulkheadResult* = object
    allowed*: bool
    capacity*: int
    inUse*: int
    remaining*: int

  Bulkhead* = object
    capacity: int
    current: int

proc resultFor(limiter: Bulkhead; allowed: bool): BulkheadResult =
  BulkheadResult(
    allowed: allowed,
    capacity: limiter.capacity,
    inUse: limiter.current,
    remaining: max(0, limiter.capacity - limiter.current)
  )

proc initBulkhead*(capacity: int): Bulkhead =
  ## Creates an in-process concurrent-work limiter.
  ##
  ## This object tracks permits. It does not provide cross-thread locking by
  ## itself; protect shared instances with the application's synchronization
  ## primitive when multiple threads mutate the same bulkhead.
  if capacity <= 0:
    raise newException(BulkheadConfigError, "capacity must be positive")
  Bulkhead(capacity: capacity)

proc inspect*(limiter: Bulkhead): BulkheadResult =
  limiter.resultFor(limiter.current < limiter.capacity)

proc acquire*(limiter: var Bulkhead): BulkheadResult =
  if limiter.current < limiter.capacity:
    inc limiter.current
    return limiter.resultFor(true)
  limiter.resultFor(false)

proc tryAcquire*(limiter: var Bulkhead): bool =
  limiter.acquire().allowed

proc release*(limiter: var Bulkhead) =
  if limiter.current <= 0:
    raise newException(BulkheadError, "no acquired permit to release")
  dec limiter.current

proc inUse*(limiter: Bulkhead): int =
  limiter.current

proc available*(limiter: Bulkhead): int =
  max(0, limiter.capacity - limiter.current)

template withBulkhead*(limiter: var Bulkhead; body: untyped): untyped =
  let acquired = limiter.acquire()
  if not acquired.allowed:
    raise newException(BulkheadError, "bulkhead capacity exceeded")
  try:
    body
  finally:
    limiter.release()
