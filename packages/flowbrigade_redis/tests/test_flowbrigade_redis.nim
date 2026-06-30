import std/[math, strutils, tables, times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/ratelimit
import flowbrigade_redis

type
  RedisEntry = object
    value: int64
    expiresAt: int64
    lastMs: int64

  FakeRedis = ref object
    entries: Table[string, RedisEntry]
    calls: seq[string]

proc initFakeRedis(): FakeRedis =
  FakeRedis(entries: initTable[string, RedisEntry]())

proc prune(redis: FakeRedis; nowMs: int64) =
  var expired: seq[string] = @[]
  for key, entry in redis.entries.pairs:
    if nowMs >= entry.expiresAt:
      expired.add(key)
  for key in expired:
    redis.entries.del(key)

proc eval(redis: FakeRedis): RedisEvalProc =
  proc(script: string; keys, args: seq[string]): seq[int64] =
    redis.calls.add(script)

    let key = keys[0]
    if script == ClearFixedWindowScript:
      let existed = redis.entries.hasKey(key)
      redis.entries.del(key)
      return @[if existed: 1'i64 else: 0'i64]

    if script == ClearTokenBucketScript:
      let existed = redis.entries.hasKey(key)
      redis.entries.del(key)
      return @[if existed: 1'i64 else: 0'i64]

    if script == InspectTokenBucketScript or script == ConsumeTokenBucketScript:
      const scale = 1_000_000'i64
      let rate = parseInt(args[0]).int64
      let perMs = parseInt(args[1]).int64
      let burst = parseInt(args[2]).int64
      let cost = parseInt(args[3]).int64
      let nowMs = redis.calls.len.int64 * 250
      let burstScaled = burst * scale
      let costScaled = cost * scale

      redis.prune(nowMs)

      let entry = redis.entries.getOrDefault(
        key,
        RedisEntry(value: burstScaled, lastMs: nowMs)
      )
      let elapsedMs = max(0'i64, nowMs - entry.lastMs)
      let tokens = min(
        burstScaled,
        entry.value + int64(float(elapsedMs * rate * scale) / float(perMs))
      )
      let remaining = tokens div scale
      let resetMs = int64(ceil(float(max(0'i64, burstScaled - tokens) * perMs) / float(rate * scale)))

      if tokens >= costScaled:
        let nextTokens = tokens - costScaled
        if script == ConsumeTokenBucketScript:
          let ttlMs = int64(ceil(float(max(1'i64, burstScaled - nextTokens) * perMs) / float(rate * scale)))
          redis.entries[key] = RedisEntry(
            value: nextTokens,
            expiresAt: nowMs + ttlMs,
            lastMs: nowMs
          )
        return @[1'i64, burst, nextTokens div scale, 0'i64, resetMs]

      let retryMs = int64(ceil(float((costScaled - tokens) * perMs) / float(rate * scale)))
      return @[0'i64, burst, remaining, retryMs, resetMs]

    let limit = parseInt(args[0])
    let cost = parseInt(args[1])
    let perMs = parseInt(args[2])
    let nowMs = redis.calls.len.int64 * 250

    redis.prune(nowMs)

    let entry = redis.entries.getOrDefault(key)
    let used = entry.value
    var resetMs = if redis.entries.hasKey(key): entry.expiresAt - nowMs else: perMs
    if resetMs < 0:
      resetMs = perMs

    if script == InspectFixedWindowScript:
      if used + cost <= limit:
        return @[1'i64, limit, limit - used - cost, 0, resetMs]
      return @[0'i64, limit, max(0'i64, limit - used), resetMs, resetMs]

    if script == ConsumeFixedWindowScript:
      if used + cost <= limit:
        let next = used + cost
        let expiresAt = if redis.entries.hasKey(key): entry.expiresAt else: nowMs + perMs
        redis.entries[key] = RedisEntry(value: next, expiresAt: expiresAt)
        resetMs = expiresAt - nowMs
        return @[1'i64, limit, limit - next, 0, resetMs]
      return @[0'i64, limit, max(0'i64, limit - used), resetMs, resetMs]

    raise newException(ValueError, "unexpected script")

proc command(redis: FakeRedis): RedisCommandProc =
  proc(command: string; args: seq[string]): seq[int64] =
    if command != "EVAL":
      raise newException(ValueError, "unexpected command")
    let script = args[0]
    let keyCount = parseInt(args[1])
    let keys = args[2 ..< 2 + keyCount]
    let scriptArgs = args[2 + keyCount .. ^1]
    redis.eval()(script, keys, scriptArgs)

suite "Redis rate limit adapter":
  test "reports adapter capabilities":
    let capabilities = redisRateLimitCapabilities()

    check capabilities.supports(rlcInspect)
    check capabilities.supports(rlcAtomicConsume)
    check capabilities.supports(rlcClear)
    check capabilities.supports(rlcTtl)
    check capabilities.supports(rlcDistributed)
    check not capabilities.supports(rlcReservation)

  test "stored fixed window uses Redis eval callbacks":
    let time = initManualTimeSource()
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval()).asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 2,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    check limiter.allow("alice")
    check limiter.allow("alice")
    check not limiter.allow("alice")
    check redis.calls.len == 3

  test "inspect does not consume Redis capacity":
    let time = initManualTimeSource()
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval()).asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    check limiter.inspect("alice").allowed
    check limiter.inspect("alice").allowed
    check limiter.allow("alice")
    check not limiter.allow("alice")

  test "can adapt a raw Redis command callback":
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorageFromCommand(redis.command()).asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage
    )

    check limiter.allow("alice")
    check not limiter.allow("alice")

  test "can clear Redis fixed window state":
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval()).asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage
    )

    check limiter.allow("alice")
    check not limiter.allow("alice")
    check limiter.clear("alice")
    check limiter.allow("alice")
    check not limiter.clear("missing")

  test "window resets after Redis ttl expires":
    let time = initManualTimeSource()
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval()).asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    check limiter.allow("alice")
    check not limiter.allow("alice")

    discard redis.eval()(ConsumeFixedWindowScript, @["advance-clock"], @["1", "1", "1000"])
    discard redis.eval()(ConsumeFixedWindowScript, @["advance-clock-2"], @["1", "1", "1000"])
    discard redis.eval()(ConsumeFixedWindowScript, @["advance-clock-3"], @["1", "1", "1000"])
    discard redis.eval()(ConsumeFixedWindowScript, @["advance-clock-4"], @["1", "1", "1000"])
    check limiter.allow("alice")

  test "returns retry metadata from Redis script":
    let time = initManualTimeSource()
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval()).asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    discard limiter.consume("alice")
    time.advance(initDuration(milliseconds = 250))
    let denied = limiter.consume("alice")
    check not denied.allowed
    check denied.retryAfter == initDuration(milliseconds = 750)
    check denied.resetAfter == initDuration(milliseconds = 750)

  test "rejects invalid Redis adapter configuration":
    expect RateLimitConfigError:
      discard initRedisRateLimitStorage(nil)

    expect RateLimitConfigError:
      discard redisEvalFromCommand(nil)

    expect RateLimitConfigError:
      discard initRedisRateLimitStorage(
        proc(script: string; keys, args: seq[string]): seq[int64] = @[],
        keyPrefix = "  "
      )

    expect RateLimitConfigError:
      discard asRateLimitStorage(RedisRateLimitStorage(nil))

  test "Redis token bucket allows up to burst capacity":
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval())
    let limiter = initRedisTokenBucket(
      storage = storage,
      key = "api:alice",
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 2
    )

    check limiter.allow()
    check limiter.allow()
    let denied = limiter.consume()
    check not denied.allowed
    check denied.retryAfter > initDuration()

  test "Redis token bucket inspect does not consume capacity":
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval())
    let limiter = initRedisTokenBucket(
      storage = storage,
      key = "api:alice",
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1
    )

    check limiter.inspect().allowed
    check limiter.inspect().allowed
    check limiter.allow()
    check not limiter.allow()

  test "Redis token bucket refills and can be cleared":
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval())
    let limiter = initRedisTokenBucket(
      storage = storage,
      key = "api:alice",
      rate = 1,
      per = initDuration(milliseconds = 500),
      burst = 1
    )

    check limiter.allow()
    check not limiter.allow()
    discard redis.eval()(ConsumeTokenBucketScript, @["advance-clock"], @["1", "500", "1", "1"])
    check limiter.allow()
    check not limiter.allow()
    check limiter.clear()
    check limiter.allow()

  test "Redis token bucket rejects invalid configuration and costs":
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval())

    expect RateLimitConfigError:
      discard initRedisTokenBucket(storage, "key", 0, initDuration(seconds = 1), 1)

    expect RateLimitConfigError:
      discard initRedisTokenBucket(storage, "key", 1, initDuration(), 1)

    expect RateLimitConfigError:
      discard initRedisTokenBucket(storage, "  ", 1, initDuration(seconds = 1), 1)

    let limiter = initRedisTokenBucket(storage, "key", 1, initDuration(seconds = 1), 1)
    expect RateLimitError:
      discard limiter.consume(0)

    expect RateLimitError:
      discard limiter.consume(2)

  test "Redis keyed token bucket tracks keys independently":
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval())
    let limiter = initRedisKeyedTokenBucket(
      storage = storage,
      namespace = "api",
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1
    )

    check limiter.allow("alice")
    check not limiter.allow("alice")
    check limiter.allow("bob")
    check not limiter.allow("bob")

  test "Redis keyed token bucket inspect does not consume capacity":
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval())
    let limiter = initRedisKeyedTokenBucket(
      storage = storage,
      namespace = "api",
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1
    )

    check limiter.inspect("alice").allowed
    check limiter.inspect("alice").allowed
    check limiter.allow("alice")
    check not limiter.allow("alice")

  test "Redis keyed token bucket clears one key":
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval())
    let limiter = initRedisKeyedTokenBucket(
      storage = storage,
      namespace = "api",
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1
    )

    check limiter.allow("alice")
    check not limiter.allow("alice")
    check limiter.allow("bob")
    check limiter.clear("alice")
    check limiter.allow("alice")
    check not limiter.allow("bob")
    check not limiter.clear("missing")

  test "Redis keyed token bucket rejects invalid configuration keys and costs":
    let redis = initFakeRedis()
    let storage = initRedisRateLimitStorage(redis.eval())

    expect RateLimitConfigError:
      discard initRedisKeyedTokenBucket(storage, " ", 1, initDuration(seconds = 1), 1)
    expect RateLimitConfigError:
      discard initRedisKeyedTokenBucket(storage, "api", 0, initDuration(seconds = 1), 1)

    let limiter = initRedisKeyedTokenBucket(storage, "api", 1, initDuration(seconds = 1), 1)
    expect RateLimitError:
      discard limiter.consume("")
    expect RateLimitError:
      discard limiter.consume(" ")
    expect RateLimitError:
      discard limiter.consume("alice" & chr(10))
    expect RateLimitError:
      discard limiter.consume("alice", cost = 0)
    expect RateLimitError:
      discard limiter.consume("alice", cost = 2)
