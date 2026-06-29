import ready

import flowbrigade/ratelimit
import flowbrigade_redis

export flowbrigade_redis

proc readyRateLimitCapabilities*(): RateLimitCapabilities =
  ## Describes guarantees inherited from the Redis Lua-script adapter.
  redisRateLimitCapabilities()

proc readyReplyToIntSeq*(reply: RedisReply): seq[int64] =
  ## Converts a `ready.RedisReply` array into integer script output.
  try:
    for value in reply.to(seq[int]):
      result.add(value.int64)
  except ready.RedisError as exc:
    raise newException(RateLimitError, exc.msg)

proc readyCommandProc*(conn: RedisConn): RedisCommandProc =
  ## Adapts a `ready.RedisConn` to FlowBrigade's Redis command callback.
  if conn.isNil:
    raise newException(RateLimitConfigError, "Redis connection must not be nil")
  proc(command: string; args: seq[string]): seq[int64] =
    conn.command(command, args).readyReplyToIntSeq()

proc initReadyRateLimitStorage*(
    conn: RedisConn;
    keyPrefix = "flowbrigade"
): RedisRateLimitStorage =
  ## Creates Redis storage backed by the `ready` OSS package.
  initRedisRateLimitStorageFromCommand(
    command = readyCommandProc(conn),
    keyPrefix = keyPrefix
  )
