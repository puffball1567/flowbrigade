import std/[net, os, strutils, times]

import flowbrigade_redis

const DefaultIterations = 10_000

proc redisHost(): string =
  getEnv("FLOWBRIGADE_REDIS_HOST", "127.0.0.1")

proc redisPort(): Port =
  Port(parseInt(getEnv("FLOWBRIGADE_REDIS_PORT", "6379")))

proc iterations(): int =
  parseInt(getEnv("FLOWBRIGADE_REDIS_BENCH_ITERATIONS", $DefaultIterations))

proc readRespLine(socket: Socket): string =
  while true:
    let chunk = socket.recv(1)
    if chunk.len == 0:
      raise newException(IOError, "Redis connection closed")
    if chunk[0] == '\L':
      if result.len > 0 and result[^1] == '\c':
        result.setLen(result.len - 1)
      return
    result.add(chunk)

proc readBytes(socket: Socket; length: int): string =
  while result.len < length:
    let chunk = socket.recv(length - result.len)
    if chunk.len == 0:
      raise newException(IOError, "Redis connection closed")
    result.add(chunk)

proc readRespInt(socket: Socket): int64

proc skipBulk(socket: Socket) =
  let lengthLine = socket.readRespLine()
  let length = parseInt(lengthLine)
  if length >= 0:
    discard socket.readBytes(length)
    discard socket.readBytes(2)

proc readRespInt(socket: Socket): int64 =
  let prefix = socket.recv(1)
  if prefix.len == 0:
    raise newException(IOError, "Redis connection closed")

  case prefix[0]
  of ':':
    parseBiggestInt(socket.readRespLine()).int64
  of '-':
    raise newException(IOError, socket.readRespLine())
  of '$':
    socket.skipBulk()
    raise newException(IOError, "expected Redis integer, got bulk string")
  else:
    raise newException(IOError, "unexpected Redis response prefix: " & prefix)

proc readRespIntArray(socket: Socket): seq[int64] =
  let prefix = socket.recv(1)
  if prefix.len == 0:
    raise newException(IOError, "Redis connection closed")
  if prefix[0] == '-':
    raise newException(IOError, socket.readRespLine())
  if prefix[0] != '*':
    raise newException(IOError, "expected Redis array response")

  let count = parseInt(socket.readRespLine())
  if count < 0:
    return @[]
  for _ in 0 ..< count:
    result.add(socket.readRespInt())

proc encodeCommand(parts: openArray[string]): string =
  result = "*" & $parts.len & "\r\n"
  for part in parts:
    result.add("$" & $part.len & "\r\n")
    result.add(part)
    result.add("\r\n")

proc sendCommand(socket: Socket; parts: openArray[string]) =
  socket.send(encodeCommand(parts))

proc connectRedis(): Socket =
  result = newSocket()
  result.connect(redisHost(), redisPort(), timeout = 500)

proc evalWithSocket(socket: Socket): RedisEvalProc =
  proc(script: string; keys: seq[string]; args: seq[string]): seq[int64] =
    socket.sendCommand(@["EVAL", script, $keys.len] & keys & args)
    socket.readRespIntArray()

template bench(name: string; body: untyped) =
  block:
    let started = cpuTime()
    body
    let elapsed = cpuTime() - started
    echo name, ": ", elapsed.formatFloat(ffDecimal, 6), "s"

proc main() =
  let socket =
    try:
      connectRedis()
    except CatchableError as exc:
      echo "SKIP: Redis is not running at ", redisHost(), ":", redisPort(), " (", exc.msg, ")"
      return
  defer: socket.close()

  let count = iterations()
  let storage = initRedisRateLimitStorage(evalWithSocket(socket), "flowbrigade:bench:" & $getCurrentProcessId())

  bench "redis token bucket real-server consume":
    let limiter = initRedisTokenBucket(
      storage = storage,
      key = "token",
      rate = count,
      per = initDuration(seconds = 1),
      burst = count
    )
    var allowed = 0
    for _ in 0 ..< count:
      if limiter.allow():
        inc allowed
    doAssert allowed == count
    discard limiter.clear()

  bench "redis keyed token bucket real-server consume":
    let limiter = initRedisKeyedTokenBucket(
      storage = storage,
      namespace = "token",
      rate = count,
      per = initDuration(seconds = 1),
      burst = count
    )
    var allowed = 0
    for i in 0 ..< count:
      if limiter.allow("user-" & $(i mod 100)):
        inc allowed
    doAssert allowed == count
    for i in 0 ..< 100:
      discard limiter.clear("user-" & $i)

main()
