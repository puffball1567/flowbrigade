import std/[strutils, tables, times]

import ./errors
import ./fixed_window
import ./key_builder
import ./keyed
import ./result
import ./sliding_window
import ./storage
import ./token_bucket

type
  LimiterDefinitionKind* = enum
    ldkFixedWindow,
    ldkSlidingWindow,
    ldkTokenBucket,
    ldkKeyedFixedWindow

  LimiterDefinition* = object
    kind*: LimiterDefinitionKind
    limit*: int
    per*: Duration
    rate*: int
    burst*: int
    maxKeys*: int

  LimiterInspectProc* = proc(key: string; cost: int): RateLimitResult {.closure.}
  LimiterConsumeProc* = proc(key: string; cost: int): RateLimitResult {.closure.}
  LimiterClearProc* = proc(key: string): bool {.closure.}

  LimiterHandle* = object
    inspect*: LimiterInspectProc
    consume*: LimiterConsumeProc
    clear*: LimiterClearProc

  LimiterRegistry* = object
    limiters: Table[string, LimiterHandle]

proc validateName(name: string) =
  try:
    discard rateLimitKey([name], maxPartLength = 128)
  except RateLimitError as exc:
    raise newException(RateLimitConfigError, exc.msg)

proc validateRegistryKey(key: string) =
  if key.len == 0:
    raise newException(RateLimitError, "key must not be empty")
  if key.strip().len == 0:
    raise newException(RateLimitError, "key must not be blank")
  if key.len > DefaultMaxRateLimitKeyLength:
    raise newException(RateLimitError, "key is too long")
  for ch in key:
    if ord(ch) < 32 or ord(ch) == 127:
      raise newException(RateLimitError, "key must not contain control characters")

proc validateHandle(handle: LimiterHandle) =
  if handle.inspect.isNil:
    raise newException(RateLimitConfigError, "limiter inspect proc must not be nil")
  if handle.consume.isNil:
    raise newException(RateLimitConfigError, "limiter consume proc must not be nil")

proc initLimiterRegistry*(): LimiterRegistry =
  LimiterRegistry(limiters: initTable[string, LimiterHandle]())

proc getLimiter(registry: LimiterRegistry; name: string): LimiterHandle

proc fixedWindowDefinition*(limit: int; per: Duration): LimiterDefinition =
  LimiterDefinition(kind: ldkFixedWindow, limit: limit, per: per)

proc slidingWindowDefinition*(limit: int; per: Duration): LimiterDefinition =
  LimiterDefinition(kind: ldkSlidingWindow, limit: limit, per: per)

proc tokenBucketDefinition*(
    rate: int;
    per: Duration;
    burst: int
): LimiterDefinition =
  LimiterDefinition(kind: ldkTokenBucket, rate: rate, per: per, burst: burst)

proc keyedFixedWindowDefinition*(
    limit: int;
    per: Duration;
    maxKeys = DefaultMaxKeys
): LimiterDefinition =
  LimiterDefinition(
    kind: ldkKeyedFixedWindow,
    limit: limit,
    per: per,
    maxKeys: maxKeys
  )

proc addLimiter*(
    registry: var LimiterRegistry;
    name: string;
    handle: LimiterHandle
) =
  validateName(name)
  validateHandle(handle)
  if registry.limiters.hasKey(name):
    raise newException(RateLimitConfigError, "limiter already exists")
  registry.limiters[name] = handle

proc addLimiter*(
    registry: var LimiterRegistry;
    name: string;
    definition: LimiterDefinition
) =
  validateName(name)
  if registry.limiters.hasKey(name):
    raise newException(RateLimitConfigError, "limiter already exists")

  case definition.kind
  of ldkFixedWindow:
    var limiter = initFixedWindow(definition.limit, definition.per)
    registry.addLimiter(name, LimiterHandle(
      inspect: proc(key: string; cost: int): RateLimitResult =
        limiter.inspect(cost),
      consume: proc(key: string; cost: int): RateLimitResult =
        limiter.consume(cost),
      clear: proc(key: string): bool = false
    ))
  of ldkSlidingWindow:
    var limiter = initSlidingWindow(definition.limit, definition.per)
    registry.addLimiter(name, LimiterHandle(
      inspect: proc(key: string; cost: int): RateLimitResult =
        limiter.inspect(cost),
      consume: proc(key: string; cost: int): RateLimitResult =
        limiter.consume(cost),
      clear: proc(key: string): bool = false
    ))
  of ldkTokenBucket:
    var limiter = initTokenBucket(definition.rate, definition.per, definition.burst)
    registry.addLimiter(name, LimiterHandle(
      inspect: proc(key: string; cost: int): RateLimitResult =
        limiter.inspect(cost),
      consume: proc(key: string; cost: int): RateLimitResult =
        limiter.consume(cost),
      clear: proc(key: string): bool = false
    ))
  of ldkKeyedFixedWindow:
    var limiter = initKeyedFixedWindow[string](
      definition.limit,
      definition.per,
      maxKeys = definition.maxKeys
    )
    registry.addLimiter(name, LimiterHandle(
      inspect: proc(key: string; cost: int): RateLimitResult =
        validateRegistryKey(key)
        limiter.inspect(key, cost),
      consume: proc(key: string; cost: int): RateLimitResult =
        validateRegistryKey(key)
        limiter.consume(key, cost),
      clear: proc(key: string): bool = false
    ))

proc addStoredFixedWindow*(
    registry: var LimiterRegistry;
    name: string;
    prefix: string;
    limit: int;
    per: Duration;
    storage: RateLimitStorage;
    maxKeyLength = DefaultMaxRateLimitKeyLength
) =
  var limiter = initStoredFixedWindow(
    prefix = prefix,
    limit = limit,
    per = per,
    storage = storage,
    maxKeyLength = maxKeyLength
  )
  registry.addLimiter(name, LimiterHandle(
    inspect: proc(key: string; cost: int): RateLimitResult =
      limiter.inspect(key, cost),
    consume: proc(key: string; cost: int): RateLimitResult =
      limiter.consume(key, cost),
    clear: proc(key: string): bool =
      limiter.clear(key)
  ))

proc maxDuration(a, b: Duration): Duration =
  if a >= b: a else: b

proc minDuration(a, b: Duration): Duration =
  if a <= b: a else: b

proc combineRegistryResults(results: openArray[RateLimitResult]): RateLimitResult =
  doAssert results.len > 0

  var allowed = true
  var limit = results[0].limit
  var remaining = results[0].remaining
  var retryAfter = initDuration()
  var resetAfter = results[0].resetAfter

  for item in results:
    allowed = allowed and item.allowed
    limit = min(limit, item.limit)
    remaining = min(remaining, item.remaining)
    if item.allowed:
      resetAfter = minDuration(resetAfter, item.resetAfter)
    else:
      retryAfter = maxDuration(retryAfter, item.retryAfter)
      resetAfter = maxDuration(resetAfter, item.resetAfter)

  if allowed:
    return allowedResult(limit = limit, remaining = remaining, resetAfter = resetAfter)

  deniedResult(
    limit = limit,
    remaining = remaining,
    retryAfter = retryAfter,
    resetAfter = resetAfter
  )

proc addCompoundLimiter*(
    registry: var LimiterRegistry;
    name: string;
    limiterNames: openArray[string]
) =
  validateName(name)
  if limiterNames.len == 0:
    raise newException(RateLimitConfigError, "compound limiter needs at least one limiter")
  if registry.limiters.hasKey(name):
    raise newException(RateLimitConfigError, "limiter already exists")

  var handles: seq[LimiterHandle] = @[]
  for childName in limiterNames:
    handles.add(registry.getLimiter(childName))

  registry.addLimiter(name, LimiterHandle(
    inspect: proc(key: string; cost: int): RateLimitResult =
      var results: seq[RateLimitResult] = @[]
      for handle in handles:
        results.add(handle.inspect(key, cost))
      combineRegistryResults(results),
    consume: proc(key: string; cost: int): RateLimitResult =
      var inspected: seq[RateLimitResult] = @[]
      for handle in handles:
        inspected.add(handle.inspect(key, cost))
      let checked = combineRegistryResults(inspected)
      if not checked.allowed:
        return checked

      var consumed: seq[RateLimitResult] = @[]
      for handle in handles:
        consumed.add(handle.consume(key, cost))
      combineRegistryResults(consumed),
    clear: proc(key: string): bool =
      result = false
      for handle in handles:
        if not handle.clear.isNil:
          result = handle.clear(key) or result
  ))

proc hasLimiter*(registry: LimiterRegistry; name: string): bool =
  registry.limiters.hasKey(name)

proc limiterNames*(registry: LimiterRegistry): seq[string] =
  for name in registry.limiters.keys:
    result.add(name)

proc getLimiter(registry: LimiterRegistry; name: string): LimiterHandle =
  if not registry.limiters.hasKey(name):
    raise newException(RateLimitError, "unknown limiter")
  registry.limiters[name]

proc inspect*(
    registry: LimiterRegistry;
    name: string;
    key = "global";
    cost = 1
): RateLimitResult =
  registry.getLimiter(name).inspect(key, cost)

proc consume*(
    registry: LimiterRegistry;
    name: string;
    key = "global";
    cost = 1
): RateLimitResult =
  registry.getLimiter(name).consume(key, cost)

proc allow*(
    registry: LimiterRegistry;
    name: string;
    key = "global";
    cost = 1
): bool =
  registry.consume(name, key, cost).allowed

proc clear*(
    registry: LimiterRegistry;
    name: string;
    key = "global"
): bool =
  let handle = registry.getLimiter(name)
  if handle.clear.isNil:
    return false
  handle.clear(key)
