import std/[os, osproc, streams, strutils, times, unittest]

import flowbrigade/ratelimit
import flowbrigade_redis

proc redisCliAvailable(): bool =
  findExe("redis-cli").len > 0

proc redisHost(): string =
  getEnv("FLOWBRIGADE_REDIS_HOST", "127.0.0.1")

proc redisPort(): string =
  getEnv("FLOWBRIGADE_REDIS_PORT", "6379")

proc redisCli(args: openArray[string]): tuple[output: string; exitCode: int] =
  let process = startProcess(
    "redis-cli",
    args = @["-h", redisHost(), "-p", redisPort()] & @args,
    options = {poUsePath, poStdErrToStdOut}
  )
  let output = process.outputStream.readAll()
  let exitCode = process.waitForExit()
  process.close()
  (output: output, exitCode: exitCode)

proc redisRunning(): bool =
  let ping = redisCli(["PING"])
  ping.exitCode == 0 and ping.output.strip() == "PONG"

proc evalWithRedisCli(
    script: string;
    keys: seq[string];
    args: seq[string]
): seq[int64] =
  let command = @["--raw", "EVAL", script, $keys.len] & keys & args
  let response = redisCli(command)
  if response.exitCode != 0:
    raise newException(RateLimitError, response.output.strip())

  for line in response.output.strip().splitLines:
    if line.len > 0:
      result.add(parseBiggestInt(line).int64)

if not redisCliAvailable():
  echo "SKIP: redis-cli is not installed"
elif not redisRunning():
  echo "SKIP: Redis is not running at ", redisHost(), ":", redisPort()
else:
  suite "Redis adapter integration":
    test "uses Redis scripts atomically against a real Redis server":
      let keyPrefix = "flowbrigade:test:" & $getCurrentProcessId()
      let storage = initRedisRateLimitStorage(evalWithRedisCli, keyPrefix).asRateLimitStorage()
      let limiter = initStoredFixedWindow(
        prefix = "api",
        limit = 1,
        per = initDuration(milliseconds = 500),
        storage = storage
      )

      check limiter.allow("alice")
      let denied = limiter.consume("alice")
      check not denied.allowed
      check denied.retryAfter > initDuration()

      check limiter.clear("alice")
      check limiter.allow("alice")

      sleep(650)
      check limiter.allow("alice")

    test "uses Redis token bucket scripts against a real Redis server":
      let keyPrefix = "flowbrigade:test:" & $getCurrentProcessId()
      let storage = initRedisRateLimitStorage(evalWithRedisCli, keyPrefix)
      let limiter = initRedisTokenBucket(
        storage = storage,
        key = "token:alice",
        rate = 1,
        per = initDuration(milliseconds = 500),
        burst = 1
      )

      check limiter.allow()
      let denied = limiter.consume()
      check not denied.allowed
      check denied.retryAfter > initDuration()

      sleep(650)
      check limiter.allow()

      check limiter.clear()
