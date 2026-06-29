import std/[os, strutils, times, unittest]

import ready

import flowbrigade/ratelimit
import flowbrigade_ready

proc redisHost(): string =
  getEnv("FLOWBRIGADE_REDIS_HOST", "127.0.0.1")

proc redisPort(): Port =
  Port(parseInt(getEnv("FLOWBRIGADE_REDIS_PORT", "6379")))

proc redisAvailable(): bool =
  var conn: RedisConn
  try:
    conn = newRedisConn(redisHost(), redisPort())
    conn.command("PING").to(string) == "PONG"
  except CatchableError:
    false
  finally:
    if not conn.isNil:
      conn.close()

if not redisAvailable():
  echo "SKIP: Redis is not running at ", redisHost(), ":", redisPort().int
else:
  suite "ready bridge integration":
    test "ready bridge supports stored fixed window":
      let keyPrefix = "flowbrigade:ready:test:" & $getCurrentProcessId()
      let conn = newRedisConn(redisHost(), redisPort())
      let storage = initReadyRateLimitStorage(conn, keyPrefix).asRateLimitStorage()
      let limiter = initStoredFixedWindow(
        prefix = "api",
        limit = 1,
        per = initDuration(milliseconds = 500),
        storage = storage
      )

      check limiter.allow("alice")
      check not limiter.allow("alice")
      check limiter.clear("alice")
      check limiter.allow("alice")
      conn.close()

    test "ready bridge supports Redis token bucket":
      let keyPrefix = "flowbrigade:ready:test:" & $getCurrentProcessId()
      let conn = newRedisConn(redisHost(), redisPort())
      let storage = initReadyRateLimitStorage(conn, keyPrefix)
      let bucket = initRedisTokenBucket(
        storage = storage,
        key = "token:alice",
        rate = 1,
        per = initDuration(milliseconds = 500),
        burst = 1
      )

      check bucket.allow()
      check not bucket.allow()
      check bucket.clear()
      conn.close()
