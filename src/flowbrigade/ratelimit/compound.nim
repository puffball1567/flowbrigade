import std/times

import ./errors
import ./result

type
  RateLimitProc* = proc(): RateLimitResult {.closure.}

  RateLimitRule* = object
    name*: string
    inspectProc*: RateLimitProc
    consumeProc*: RateLimitProc

  CompoundLimiter* = object
    rules: seq[RateLimitRule]

proc rateLimitRule*(
    name: string;
    inspect: RateLimitProc;
    consume: RateLimitProc
): RateLimitRule =
  if inspect.isNil:
    raise newException(RateLimitConfigError, "inspect proc must not be nil")
  if consume.isNil:
    raise newException(RateLimitConfigError, "consume proc must not be nil")
  RateLimitRule(name: name, inspectProc: inspect, consumeProc: consume)

proc initCompoundLimiter*(rules: openArray[RateLimitRule]): CompoundLimiter =
  if rules.len == 0:
    raise newException(RateLimitConfigError, "compound limiter needs at least one rule")
  CompoundLimiter(rules: @rules)

proc maxDuration(a, b: Duration): Duration =
  if a >= b: a else: b

proc minDuration(a, b: Duration): Duration =
  if a <= b: a else: b

proc combine(results: openArray[RateLimitResult]): RateLimitResult =
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
    return allowedResult(
      limit = limit,
      remaining = remaining,
      resetAfter = resetAfter
    )

  deniedResult(
    limit = limit,
    remaining = remaining,
    retryAfter = retryAfter,
    resetAfter = resetAfter
  )

proc inspect*(limiter: CompoundLimiter): RateLimitResult =
  var results: seq[RateLimitResult] = @[]
  for rule in limiter.rules:
    results.add(rule.inspectProc())
  combine(results)

proc consume*(limiter: CompoundLimiter): RateLimitResult =
  let checked = limiter.inspect()
  if not checked.allowed:
    return checked

  var results: seq[RateLimitResult] = @[]
  for rule in limiter.rules:
    results.add(rule.consumeProc())
  combine(results)

proc allow*(limiter: CompoundLimiter): bool =
  limiter.consume().allowed
