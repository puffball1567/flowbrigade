import std/[strutils, tables]

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

  KeyedBulkhead*[K] = object
    capacity: int
    maxKeys: int
    current: Table[K, int]

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

proc validateKey(key: string) =
  if key.len == 0:
    raise newException(BulkheadError, "bulkhead key must not be empty")
  if key.strip().len == 0:
    raise newException(BulkheadError, "bulkhead key must not be blank")
  for ch in key:
    if ord(ch) < 32 or ord(ch) == 127:
      raise newException(BulkheadError, "bulkhead key must not contain control characters")

proc validateKey[K](key: K) =
  when K is string:
    validateKey(key)

proc initKeyedBulkhead*[K](capacity: int; maxKeys = 10_000): KeyedBulkhead[K] =
  ## Creates an in-process concurrent-work limiter per key.
  ##
  ## This is useful when each tenant, queue, worker pool, or job class should
  ## have its own local concurrency ceiling. It does not add thread
  ## synchronization or cross-process coordination.
  if capacity <= 0:
    raise newException(BulkheadConfigError, "capacity must be positive")
  if maxKeys <= 0:
    raise newException(BulkheadConfigError, "maxKeys must be positive")
  KeyedBulkhead[K](capacity: capacity, maxKeys: maxKeys, current: initTable[K, int]())

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

proc inspect*[K](limiter: KeyedBulkhead[K]; key: K): BulkheadResult =
  validateKey(key)
  let used = limiter.current.getOrDefault(key)
  BulkheadResult(
    allowed: used < limiter.capacity,
    capacity: limiter.capacity,
    inUse: used,
    remaining: max(0, limiter.capacity - used)
  )

proc acquire*[K](limiter: var KeyedBulkhead[K]; key: K): BulkheadResult =
  validateKey(key)
  let used = limiter.current.getOrDefault(key)
  if used <= 0 and not limiter.current.hasKey(key) and limiter.current.len >= limiter.maxKeys:
    raise newException(BulkheadError, "bulkhead key capacity exceeded")
  if used < limiter.capacity:
    limiter.current[key] = used + 1
    return BulkheadResult(
      allowed: true,
      capacity: limiter.capacity,
      inUse: used + 1,
      remaining: max(0, limiter.capacity - used - 1)
    )
  BulkheadResult(
    allowed: false,
    capacity: limiter.capacity,
    inUse: used,
    remaining: 0
  )

proc tryAcquire*[K](limiter: var KeyedBulkhead[K]; key: K): bool =
  limiter.acquire(key).allowed

proc release*[K](limiter: var KeyedBulkhead[K]; key: K) =
  validateKey(key)
  let used = limiter.current.getOrDefault(key)
  if used <= 0:
    raise newException(BulkheadError, "no acquired permit to release")
  if used == 1:
    limiter.current.del(key)
  else:
    limiter.current[key] = used - 1

proc clear*[K](limiter: var KeyedBulkhead[K]; key: K): bool =
  validateKey(key)
  result = limiter.current.hasKey(key)
  limiter.current.del(key)

proc activeKeys*[K](limiter: KeyedBulkhead[K]): int =
  limiter.current.len

template withBulkhead*(limiter: var Bulkhead; body: untyped): untyped =
  let acquired = limiter.acquire()
  if not acquired.allowed:
    raise newException(BulkheadError, "bulkhead capacity exceeded")
  try:
    body
  finally:
    limiter.release()

template withBulkhead*[K](limiter: var KeyedBulkhead[K]; key: K; body: untyped): untyped =
  let acquired = limiter.acquire(key)
  if not acquired.allowed:
    raise newException(BulkheadError, "bulkhead capacity exceeded")
  try:
    body
  finally:
    limiter.release(key)
