import std/[strutils, tables, times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/ratelimit
import flowbrigade_memcached

type
  Entry = object
    value: string
    cas: int
    expiresAt: Duration

  FakeMemcached = ref object
    entries: Table[string, Entry]
    now: Duration
    casConflicts: int

proc initFakeMemcached(): FakeMemcached =
  FakeMemcached(entries: initTable[string, Entry]())

proc prune(memcached: FakeMemcached) =
  var expired: seq[string] = @[]
  for key, entry in memcached.entries.pairs:
    if memcached.now >= entry.expiresAt:
      expired.add(key)
  for key in expired:
    memcached.entries.del(key)

proc gets(memcached: FakeMemcached): MemcachedGetsProc =
  proc(key: string): MemcachedGetResult =
    memcached.prune()
    if not memcached.entries.hasKey(key):
      return MemcachedGetResult(found: false)
    let entry = memcached.entries[key]
    MemcachedGetResult(found: true, value: entry.value, cas: $entry.cas)

proc add(memcached: FakeMemcached): MemcachedAddProc =
  proc(key, value: string; ttl: Duration): bool =
    memcached.prune()
    if memcached.entries.hasKey(key):
      return false
    memcached.entries[key] = Entry(value: value, cas: 1, expiresAt: memcached.now + ttl)
    true

proc cas(memcached: FakeMemcached): MemcachedCasProc =
  proc(key, value, cas: string; ttl: Duration): bool =
    memcached.prune()
    if memcached.casConflicts > 0:
      dec memcached.casConflicts
      return false
    if not memcached.entries.hasKey(key):
      return false
    var entry = memcached.entries[key]
    if $entry.cas != cas:
      return false
    inc entry.cas
    entry.value = value
    entry.expiresAt = memcached.now + ttl
    memcached.entries[key] = entry
    true

proc delete(memcached: FakeMemcached): MemcachedDeleteProc =
  proc(key: string): bool =
    memcached.prune()
    result = memcached.entries.hasKey(key)
    memcached.entries.del(key)

proc storage(memcached: FakeMemcached; maxCasRetries = DefaultMaxCasRetries): RateLimitStorage =
  initMemcachedRateLimitStorage(
    gets = memcached.gets(),
    add = memcached.add(),
    cas = memcached.cas(),
    delete = memcached.delete(),
    keyPrefix = "test",
    maxCasRetries = maxCasRetries
  ).asRateLimitStorage()

suite "Memcached rate limit adapter":
  test "reports adapter capabilities":
    let capabilities = memcachedRateLimitCapabilities()

    check capabilities.supports(rlcInspect)
    check capabilities.supports(rlcAtomicConsume)
    check capabilities.supports(rlcClear)
    check capabilities.supports(rlcTtl)
    check capabilities.supports(rlcDistributed)
    check not capabilities.supports(rlcReservation)

  test "stored fixed window uses Memcached callbacks":
    let time = initManualTimeSource()
    let memcached = initFakeMemcached()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 2,
      per = initDuration(seconds = 1),
      storage = memcached.storage(),
      timeSource = time
    )

    check limiter.allow("alice")
    check limiter.allow("alice")
    check not limiter.allow("alice")

  test "inspect does not consume capacity":
    let time = initManualTimeSource()
    let memcached = initFakeMemcached()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = memcached.storage(),
      timeSource = time
    )

    check limiter.inspect("alice").allowed
    check limiter.inspect("alice").allowed
    check limiter.allow("alice")
    check not limiter.allow("alice")

  test "window resets after ttl expires":
    let time = initManualTimeSource()
    let memcached = initFakeMemcached()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = memcached.storage(),
      timeSource = time
    )

    check limiter.allow("alice")
    check not limiter.allow("alice")

    time.advance(initDuration(seconds = 1))
    memcached.now = initDuration(seconds = 1)
    check limiter.allow("alice")

  test "returns retry metadata":
    let time = initManualTimeSource()
    let memcached = initFakeMemcached()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = memcached.storage(),
      timeSource = time
    )

    discard limiter.consume("alice")
    time.advance(initDuration(milliseconds = 250))
    let denied = limiter.consume("alice")
    check not denied.allowed
    check denied.retryAfter == initDuration(milliseconds = 750)
    check denied.resetAfter == initDuration(milliseconds = 750)

  test "can clear Memcached fixed window state":
    let memcached = initFakeMemcached()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = memcached.storage()
    )

    check limiter.allow("alice")
    check not limiter.allow("alice")
    check limiter.clear("alice")
    check limiter.allow("alice")
    check not limiter.clear("missing")

  test "retries CAS conflicts":
    let memcached = initFakeMemcached()
    memcached.casConflicts = 2
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 2,
      per = initDuration(seconds = 1),
      storage = memcached.storage(maxCasRetries = 3)
    )

    check limiter.allow("alice")
    check limiter.allow("alice")

  test "raises when CAS retry limit is exceeded":
    let memcached = initFakeMemcached()
    memcached.casConflicts = 4
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 2,
      per = initDuration(seconds = 1),
      storage = memcached.storage(maxCasRetries = 2)
    )

    check limiter.allow("alice")
    expect RateLimitError:
      discard limiter.allow("alice")

  test "rejects invalid adapter configuration":
    let memcached = initFakeMemcached()

    expect RateLimitConfigError:
      discard initMemcachedRateLimitStorage(
        gets = nil,
        add = memcached.add(),
        cas = memcached.cas(),
        delete = memcached.delete()
      )

    expect RateLimitConfigError:
      discard initMemcachedRateLimitStorage(
        gets = memcached.gets(),
        add = memcached.add(),
        cas = memcached.cas(),
        delete = memcached.delete(),
        keyPrefix = "bad key"
      )

    expect RateLimitConfigError:
      discard initMemcachedRateLimitStorage(
        gets = memcached.gets(),
        add = memcached.add(),
        cas = memcached.cas(),
        delete = memcached.delete(),
        maxCasRetries = 0
      )

    expect RateLimitConfigError:
      discard asRateLimitStorage(MemcachedRateLimitStorage(nil))

  test "rejects malformed stored values":
    let memcached = initFakeMemcached()
    memcached.entries["test:fixed:api:alice"] = Entry(
      value: "not-a-state",
      cas: 1,
      expiresAt: initDuration(seconds = 10)
    )
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = memcached.storage()
    )

    expect RateLimitError:
      discard limiter.inspect("alice")

  test "rejects Memcached keys above protocol length":
    let memcached = initFakeMemcached()
    let limiter = initStoredFixedWindow(
      prefix = repeat("p", 120),
      limit = 1,
      per = initDuration(seconds = 1),
      storage = memcached.storage(),
      maxKeyLength = 200
    )

    expect RateLimitError:
      discard limiter.allow(repeat("k", 200))
