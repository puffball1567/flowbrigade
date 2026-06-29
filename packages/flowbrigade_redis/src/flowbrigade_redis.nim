import std/[math, strutils, times]

import flowbrigade/ratelimit

type
  RedisEvalProc* = proc(
    script: string;
    keys: seq[string];
    args: seq[string]
  ): seq[int64] {.closure.}

  RedisCommandProc* = proc(
    command: string;
    args: seq[string]
  ): seq[int64] {.closure.}

  RedisRateLimitStorage* = ref object
    eval: RedisEvalProc
    keyPrefix: string

  RedisTokenBucket* = object
    storage: RedisRateLimitStorage
    key: string
    rate: int
    per: Duration
    burst: int

proc redisRateLimitCapabilities*(): RateLimitCapabilities =
  ## Describes guarantees provided by the Redis Lua-script adapter.
  ##
  ## The adapter does not currently implement strict future-capacity
  ## reservation, so `rlcReservation` is intentionally not included.
  initRateLimitCapabilities([
    rlcInspect,
    rlcAtomicConsume,
    rlcClear,
    rlcTtl,
    rlcDistributed
  ])

const InspectFixedWindowScript* = """
local used = tonumber(redis.call("GET", KEYS[1]) or "0")
local limit = tonumber(ARGV[1])
local cost = tonumber(ARGV[2])
local per_ms = tonumber(ARGV[3])
local reset_ms = redis.call("PTTL", KEYS[1])
if reset_ms < 0 then
  reset_ms = per_ms
end
local remaining = limit - used

if used + cost <= limit then
  return {1, limit, remaining - cost, 0, reset_ms}
end

return {0, limit, math.max(0, remaining), reset_ms, reset_ms}
"""

const ConsumeFixedWindowScript* = """
local used = tonumber(redis.call("GET", KEYS[1]) or "0")
local limit = tonumber(ARGV[1])
local cost = tonumber(ARGV[2])
local per_ms = tonumber(ARGV[3])
local reset_ms = redis.call("PTTL", KEYS[1])
if reset_ms < 0 then
  reset_ms = per_ms
end

if used + cost <= limit then
  local next_used = redis.call("INCRBY", KEYS[1], cost)
  if next_used == cost or redis.call("PTTL", KEYS[1]) < 0 then
    redis.call("PEXPIRE", KEYS[1], per_ms)
    reset_ms = per_ms
  end
  return {1, limit, limit - next_used, 0, reset_ms}
end

return {0, limit, math.max(0, limit - used), reset_ms, reset_ms}
"""

const ClearFixedWindowScript* = """
return {redis.call("DEL", KEYS[1])}
"""

const InspectTokenBucketScript* = """
local scale = 1000000
local rate = tonumber(ARGV[1])
local per_ms = tonumber(ARGV[2])
local burst = tonumber(ARGV[3])
local cost = tonumber(ARGV[4])
local burst_scaled = burst * scale
local cost_scaled = cost * scale
local time = redis.call("TIME")
local now_ms = tonumber(time[1]) * 1000 + math.floor(tonumber(time[2]) / 1000)
local tokens = burst_scaled
local last_ms = now_ms
local saved = redis.call("HMGET", KEYS[1], "tokens", "last_ms")
if saved[1] then
  tokens = tonumber(saved[1])
  last_ms = tonumber(saved[2])
end

local elapsed_ms = math.max(0, now_ms - last_ms)
tokens = math.min(burst_scaled, tokens + math.floor(elapsed_ms * rate * scale / per_ms))
local remaining = math.floor(tokens / scale)
local reset_ms = math.ceil(math.max(0, burst_scaled - tokens) * per_ms / (rate * scale))

if tokens >= cost_scaled then
  return {1, burst, math.floor((tokens - cost_scaled) / scale), 0, reset_ms}
end

local retry_ms = math.ceil((cost_scaled - tokens) * per_ms / (rate * scale))
return {0, burst, remaining, retry_ms, reset_ms}
"""

const ConsumeTokenBucketScript* = """
local scale = 1000000
local rate = tonumber(ARGV[1])
local per_ms = tonumber(ARGV[2])
local burst = tonumber(ARGV[3])
local cost = tonumber(ARGV[4])
local burst_scaled = burst * scale
local cost_scaled = cost * scale
local time = redis.call("TIME")
local now_ms = tonumber(time[1]) * 1000 + math.floor(tonumber(time[2]) / 1000)
local tokens = burst_scaled
local last_ms = now_ms
local saved = redis.call("HMGET", KEYS[1], "tokens", "last_ms")
if saved[1] then
  tokens = tonumber(saved[1])
  last_ms = tonumber(saved[2])
end

local elapsed_ms = math.max(0, now_ms - last_ms)
tokens = math.min(burst_scaled, tokens + math.floor(elapsed_ms * rate * scale / per_ms))
local remaining = math.floor(tokens / scale)
local reset_ms = math.ceil(math.max(0, burst_scaled - tokens) * per_ms / (rate * scale))

if tokens >= cost_scaled then
  local next_tokens = tokens - cost_scaled
  local ttl_ms = math.ceil(math.max(1, burst_scaled - next_tokens) * per_ms / (rate * scale))
  redis.call("HSET", KEYS[1], "tokens", next_tokens, "last_ms", now_ms)
  redis.call("PEXPIRE", KEYS[1], ttl_ms)
  return {1, burst, math.floor(next_tokens / scale), 0, reset_ms}
end

local retry_ms = math.ceil((cost_scaled - tokens) * per_ms / (rate * scale))
return {0, burst, remaining, retry_ms, reset_ms}
"""

const ClearTokenBucketScript* = """
return {redis.call("DEL", KEYS[1])}
"""

proc requirePositive(name: string; value: int64) =
  if value <= 0:
    raise newException(RateLimitConfigError, name & " must be positive")

proc requirePositive(name: string; value: int) =
  if value <= 0:
    raise newException(RateLimitConfigError, name & " must be positive")

proc durationFromMillis(value: int64): Duration =
  initDuration(milliseconds = int(value))

proc millis(value: Duration): int64 =
  value.inMilliseconds

proc redisKey(storage: RedisRateLimitStorage; key: string): string =
  storage.keyPrefix & ":fixed:" & key

proc redisTokenBucketKey(storage: RedisRateLimitStorage; key: string): string =
  storage.keyPrefix & ":token:" & key

proc parseResult(values: seq[int64]): RateLimitResult =
  if values.len != 5:
    raise newException(RateLimitError, "Redis rate limit script returned an invalid result")

  if values[0] == 1:
    return allowedResult(
      limit = int(values[1]),
      remaining = int(values[2]),
      resetAfter = durationFromMillis(values[4])
    )

  deniedResult(
    limit = int(values[1]),
    remaining = int(values[2]),
    retryAfter = durationFromMillis(values[3]),
    resetAfter = durationFromMillis(values[4])
  )

proc parseBoolResult(values: seq[int64]): bool =
  if values.len != 1:
    raise newException(RateLimitError, "Redis rate limit script returned an invalid clear result")
  values[0] > 0

proc validateTokenBucketConfig(rate: int; per: Duration; burst: int; key: string) =
  requirePositive("rate", rate)
  requirePositive("per", per.millis())
  requirePositive("burst", burst)
  if key.strip().len == 0:
    raise newException(RateLimitConfigError, "key must not be empty")

proc validateTokenBucketCost(burst, cost: int) =
  if cost <= 0:
    raise newException(RateLimitError, "cost must be positive")
  if cost > burst:
    raise newException(RateLimitError, "cost must not exceed burst capacity")

proc runFixedWindowScript(
    storage: RedisRateLimitStorage;
    script: string;
    key: string;
    limit: int;
    per: Duration;
    cost: int;
    current: Duration
): RateLimitResult =
  let perMs = per.millis()
  requirePositive("per", perMs)

  discard current
  let values = storage.eval(
    script,
    @[storage.redisKey(key)],
    @[$limit, $cost, $perMs]
  )
  parseResult(values)

proc initRedisRateLimitStorage*(
    eval: RedisEvalProc;
    keyPrefix = "flowbrigade"
): RedisRateLimitStorage =
  if eval.isNil:
    raise newException(RateLimitConfigError, "Redis eval proc must not be nil")
  if keyPrefix.strip().len == 0:
    raise newException(RateLimitConfigError, "keyPrefix must not be empty")
  RedisRateLimitStorage(eval: eval, keyPrefix: keyPrefix)

proc redisEvalFromCommand*(command: RedisCommandProc): RedisEvalProc =
  if command.isNil:
    raise newException(RateLimitConfigError, "Redis command proc must not be nil")

  proc(script: string; keys, args: seq[string]): seq[int64] =
    command("EVAL", @[script, $keys.len] & keys & args)

proc initRedisRateLimitStorageFromCommand*(
    command: RedisCommandProc;
    keyPrefix = "flowbrigade"
): RedisRateLimitStorage =
  initRedisRateLimitStorage(
    eval = redisEvalFromCommand(command),
    keyPrefix = keyPrefix
  )

proc asRateLimitStorage*(storage: RedisRateLimitStorage): RateLimitStorage =
  if storage.isNil:
    raise newException(RateLimitConfigError, "storage must not be nil")
  RateLimitStorage(
    inspectFixedWindow: proc(
      key: string;
      limit: int;
      per: Duration;
      cost: int;
      current: Duration
    ): RateLimitResult =
      storage.runFixedWindowScript(
        InspectFixedWindowScript,
        key,
        limit,
        per,
        cost,
        current
      ),
    consumeFixedWindow: proc(
      key: string;
      limit: int;
      per: Duration;
      cost: int;
      current: Duration
    ): RateLimitResult =
      storage.runFixedWindowScript(
        ConsumeFixedWindowScript,
        key,
        limit,
        per,
        cost,
        current
      ),
    clearFixedWindow: proc(key: string): bool =
      parseBoolResult(storage.eval(ClearFixedWindowScript, @[storage.redisKey(key)], @[]))
  )

proc initRedisTokenBucket*(
    storage: RedisRateLimitStorage;
    key: string;
    rate: int;
    per: Duration;
    burst: int
): RedisTokenBucket =
  ## Creates a Redis-backed token bucket limiter.
  ##
  ## Redis server time is used inside the Lua script, so the refill calculation
  ## stays consistent across processes that share the same Redis instance.
  if storage.isNil:
    raise newException(RateLimitConfigError, "storage must not be nil")
  validateTokenBucketConfig(rate, per, burst, key)
  RedisTokenBucket(storage: storage, key: key, rate: rate, per: per, burst: burst)

proc runTokenBucketScript(
    limiter: RedisTokenBucket;
    script: string;
    cost: int
): RateLimitResult =
  validateTokenBucketCost(limiter.burst, cost)
  let perMs = limiter.per.millis()
  requirePositive("per", perMs)
  parseResult(limiter.storage.eval(
    script,
    @[limiter.storage.redisTokenBucketKey(limiter.key)],
    @[$limiter.rate, $perMs, $limiter.burst, $cost]
  ))

proc inspect*(limiter: RedisTokenBucket; cost = 1): RateLimitResult =
  ## Checks Redis token bucket capacity without consuming tokens.
  limiter.runTokenBucketScript(InspectTokenBucketScript, cost)

proc consume*(limiter: RedisTokenBucket; cost = 1): RateLimitResult =
  ## Checks and consumes Redis token bucket capacity atomically.
  limiter.runTokenBucketScript(ConsumeTokenBucketScript, cost)

proc allow*(limiter: RedisTokenBucket; cost = 1): bool =
  ## Convenience boolean wrapper around `consume`.
  limiter.consume(cost).allowed

proc clear*(limiter: RedisTokenBucket): bool =
  ## Removes the Redis key for this token bucket.
  parseBoolResult(
    limiter.storage.eval(ClearTokenBucketScript, @[limiter.storage.redisTokenBucketKey(limiter.key)], @[])
  )
