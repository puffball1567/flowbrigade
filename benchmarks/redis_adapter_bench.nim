import std/[math, strutils, tables, times]

import flowbrigade_redis

const Iterations = 100_000

type
  RedisEntry = object
    value: int64
    expiresAt: int64
    lastMs: int64

  FakeRedis = ref object
    entries: Table[string, RedisEntry]
    calls: int

proc initFakeRedis(): FakeRedis =
  FakeRedis(entries: initTable[string, RedisEntry]())

proc eval(redis: FakeRedis): RedisEvalProc =
  proc(script: string; keys, args: seq[string]): seq[int64] =
    inc redis.calls

    let key = keys[0]
    if script == ClearTokenBucketScript:
      let existed = redis.entries.hasKey(key)
      redis.entries.del(key)
      return @[if existed: 1'i64 else: 0'i64]

    if script != InspectTokenBucketScript and script != ConsumeTokenBucketScript:
      raise newException(ValueError, "unexpected script")

    const scale = 1_000_000'i64
    let rate = parseInt(args[0]).int64
    let perMs = parseInt(args[1]).int64
    let burst = parseInt(args[2]).int64
    let cost = parseInt(args[3]).int64
    let nowMs = redis.calls.int64
    let burstScaled = burst * scale
    let costScaled = cost * scale

    let entry = redis.entries.getOrDefault(
      key,
      RedisEntry(value: burstScaled, expiresAt: nowMs + perMs, lastMs: nowMs)
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
    @[0'i64, burst, remaining, retryMs, resetMs]

template bench(name: string; body: untyped) =
  block:
    let started = cpuTime()
    body
    let elapsed = cpuTime() - started
    echo name, ": ", elapsed.formatFloat(ffDecimal, 6), "s"

bench "redis token bucket fake-eval consume 100k":
  let redis = initFakeRedis()
  let storage = initRedisRateLimitStorage(redis.eval())
  let limiter = initRedisTokenBucket(
    storage = storage,
    key = "api",
    rate = Iterations,
    per = initDuration(seconds = 1),
    burst = Iterations
  )
  var allowed = 0
  for _ in 0 ..< Iterations:
    if limiter.allow():
      inc allowed
  doAssert allowed == Iterations

bench "redis keyed token bucket fake-eval consume 100k":
  let redis = initFakeRedis()
  let storage = initRedisRateLimitStorage(redis.eval())
  let limiter = initRedisKeyedTokenBucket(
    storage = storage,
    namespace = "api",
    rate = Iterations,
    per = initDuration(seconds = 1),
    burst = Iterations
  )
  var allowed = 0
  for i in 0 ..< Iterations:
    if limiter.allow("user-" & $(i mod 100)):
      inc allowed
  doAssert allowed == Iterations
