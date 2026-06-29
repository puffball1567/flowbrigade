import std/times

import ready

import flowbrigade/ratelimit
import flowbrigade_ready

proc buildLimiter(conn: RedisConn): StoredFixedWindow =
  let storage = initReadyRateLimitStorage(conn).asRateLimitStorage()
  initStoredFixedWindow(
    prefix = "api",
    limit = 100,
    per = initDuration(minutes = 1),
    storage = storage
  )

when isMainModule:
  discard
