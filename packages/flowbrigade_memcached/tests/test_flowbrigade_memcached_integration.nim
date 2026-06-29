import std/[net, os, strutils, times, unittest]

import flowbrigade/ratelimit
import flowbrigade_memcached

proc memcachedHost(): string =
  getEnv("FLOWBRIGADE_MEMCACHED_HOST", "127.0.0.1")

proc memcachedPort(): Port =
  Port(parseInt(getEnv("FLOWBRIGADE_MEMCACHED_PORT", "11211")))

proc readLine(socket: Socket): string =
  socket.recvLine().strip(leading = false, trailing = true)

proc memcachedAvailable(): tuple[available: bool; reason: string] =
  try:
    let socket = newSocket()
    defer: socket.close()
    socket.connect(memcachedHost(), memcachedPort(), timeout = 500)
    socket.send("version\r\n")
    let line = socket.readLine()
    if line.startsWith("VERSION "):
      return (available: true, reason: "")
    (available: false, reason: "unexpected response to version: " & line)
  except OSError as exc:
    (available: false, reason: "cannot connect to " & memcachedHost() & ":" & $memcachedPort().int & " (" & exc.msg & ")")
  except CatchableError as exc:
    (available: false, reason: exc.msg)

type
  TextMemcached = ref object
    host: string
    port: Port

proc initTextMemcached(): TextMemcached =
  TextMemcached(host: memcachedHost(), port: memcachedPort())

proc command(client: TextMemcached; request: string): seq[string] =
  let socket = newSocket()
  defer: socket.close()
  socket.connect(client.host, client.port, timeout = 500)
  socket.send(request)
  while true:
    let line = socket.readLine()
    result.add(line)
    if line in ["END", "STORED", "NOT_STORED", "EXISTS", "NOT_FOUND", "DELETED"]:
      break
    if line.startsWith("ERROR") or line.startsWith("CLIENT_ERROR") or line.startsWith("SERVER_ERROR"):
      raise newException(RateLimitError, line)

proc ttlSeconds(ttl: Duration): int =
  let millis = ttl.inMilliseconds
  if millis <= 0:
    return 1
  max(1, int((millis + 999'i64) div 1000'i64))

proc getsProc(client: TextMemcached): MemcachedGetsProc =
  proc(key: string): MemcachedGetResult =
    let lines = client.command("gets " & key & "\r\n")
    if lines.len == 1 and lines[0] == "END":
      return MemcachedGetResult(found: false)
    if lines.len < 3 or not lines[0].startsWith("VALUE "):
      raise newException(RateLimitError, "unexpected gets response: " & lines.join(" | "))

    let header = lines[0].splitWhitespace()
    if header.len != 5:
      raise newException(RateLimitError, "unexpected gets header: " & lines[0])
    MemcachedGetResult(found: true, value: lines[1], cas: header[4])

proc addProc(client: TextMemcached): MemcachedAddProc =
  proc(key, value: string; ttl: Duration): bool =
    let request = "add " & key & " 0 " & $ttl.ttlSeconds() & " " & $value.len & "\r\n" &
      value & "\r\n"
    let lines = client.command(request)
    lines.len > 0 and lines[^1] == "STORED"

proc casProc(client: TextMemcached): MemcachedCasProc =
  proc(key, value, cas: string; ttl: Duration): bool =
    let request = "cas " & key & " 0 " & $ttl.ttlSeconds() & " " & $value.len & " " & cas & "\r\n" &
      value & "\r\n"
    let lines = client.command(request)
    lines.len > 0 and lines[^1] == "STORED"

proc deleteProc(client: TextMemcached): MemcachedDeleteProc =
  proc(key: string): bool =
    let lines = client.command("delete " & key & "\r\n")
    lines.len > 0 and lines[^1] == "DELETED"

proc rateLimitStorage(client: TextMemcached; keyPrefix: string): RateLimitStorage =
  initMemcachedRateLimitStorage(
    gets = client.getsProc(),
    add = client.addProc(),
    cas = client.casProc(),
    delete = client.deleteProc(),
    keyPrefix = keyPrefix
  ).asRateLimitStorage()

let availability = memcachedAvailable()

if not availability.available:
  echo "SKIP: Memcached integration test skipped: ", availability.reason
else:
  suite "Memcached adapter integration":
    test "uses Memcached text protocol callbacks against a real server":
      let keyPrefix = "flowbrigade:memcached:test:" & $getCurrentProcessId()
      let client = initTextMemcached()
      let limiter = initStoredFixedWindow(
        prefix = "api",
        limit = 1,
        per = initDuration(seconds = 1),
        storage = client.rateLimitStorage(keyPrefix)
      )

      check limiter.allow("alice")
      let denied = limiter.consume("alice")
      check not denied.allowed
      check denied.retryAfter > initDuration()

      check limiter.clear("alice")
      check limiter.allow("alice")

      sleep(1200)
      check limiter.allow("alice")

    test "real Memcached gets/cas rejects stale CAS tokens":
      let keyPrefix = "flowbrigade:memcached:cas:test:" & $getCurrentProcessId()
      let client = initTextMemcached()
      let key = keyPrefix & ":fixed:api:alice"

      check client.addProc()(key, "1:0", initDuration(seconds = 5))
      let first = client.getsProc()(key)
      check first.found

      check client.casProc()(key, "2:0", first.cas, initDuration(seconds = 5))
      check not client.casProc()(key, "3:0", first.cas, initDuration(seconds = 5))

      check client.deleteProc()(key)
