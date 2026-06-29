import std/[times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/ratelimit

suite "rate limit storage interface":
  test "stored fixed window shares state through storage":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
    let firstLimiter = initStoredFixedWindow(
      prefix = "api",
      limit = 2,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )
    let secondLimiter = initStoredFixedWindow(
      prefix = "api",
      limit = 2,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    check firstLimiter.allow("alice")
    check secondLimiter.allow("alice")
    check not firstLimiter.allow("alice")

  test "stored fixed window separates namespaces by prefix":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
    let apiLimiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )
    let jobLimiter = initStoredFixedWindow(
      prefix = "job",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    check apiLimiter.allow("alice")
    check not apiLimiter.allow("alice")
    check jobLimiter.allow("alice")
    check not jobLimiter.allow("alice")

  test "stored fixed window inspect does not consume capacity":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
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

  test "stored fixed window resets after the window expires":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    check limiter.allow("alice")
    check not limiter.allow("alice")

    time.advance(initDuration(seconds = 1))
    check limiter.allow("alice")

  test "stored fixed window returns result metadata":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 2,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    let allowed = limiter.consume("alice", cost = 2)
    check allowed.allowed
    check allowed.remaining == 0

    time.advance(initDuration(milliseconds = 250))
    let denied = limiter.consume("alice")
    check not denied.allowed
    check denied.retryAfter == initDuration(milliseconds = 750)
    check denied.resetAfter == initDuration(milliseconds = 750)

  test "stored fixed window rejects invalid configuration":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage()

    expect RateLimitConfigError:
      discard initStoredFixedWindow(
        prefix = "",
        limit = 1,
        per = initDuration(seconds = 1),
        storage = storage,
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initStoredFixedWindow(
        prefix = "   ",
        limit = 1,
        per = initDuration(seconds = 1),
        storage = storage,
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initStoredFixedWindow(
        prefix = "api\Lbad",
        limit = 1,
        per = initDuration(seconds = 1),
        storage = storage,
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initStoredFixedWindow(
        prefix = "api",
        limit = 0,
        per = initDuration(seconds = 1),
        storage = storage,
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initStoredFixedWindow(
        prefix = "api",
        limit = 1,
        per = initDuration(seconds = 1),
        storage = storage,
        timeSource = time,
        maxKeyLength = 0
      )

    expect RateLimitConfigError:
      discard initStoredFixedWindow(
        prefix = "api",
        limit = 1,
        per = initDuration(),
        storage = storage,
        timeSource = time
      )

  test "stored fixed window rejects invalid keys and costs":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    expect RateLimitError:
      discard limiter.allow("")
    expect RateLimitError:
      discard limiter.allow("   ")
    expect RateLimitError:
      discard limiter.allow("alice\Lbob")
    expect RateLimitError:
      discard limiter.inspect("alice", cost = 0)
    expect RateLimitError:
      discard limiter.consume("alice", cost = 2)

  test "stored fixed window rejects oversized keys":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time,
      maxKeyLength = 5
    )

    check limiter.allow("alice")
    expect RateLimitError:
      discard limiter.allow("charlie")

  test "stored fixed window can clear a key":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    check limiter.allow("alice")
    check not limiter.allow("alice")
    check limiter.clear("alice")
    check limiter.allow("alice")
    check not limiter.clear("missing")

  test "stored fixed window emits audit events":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
    var events: seq[StoredFixedWindowAuditEvent] = @[]
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time,
      audit = proc(event: StoredFixedWindowAuditEvent) =
        events.add(event)
    )

    discard limiter.inspect("alice")
    discard limiter.consume("alice")
    discard limiter.clear("alice")

    check events.len == 3
    check events[0].action == sfwaInspect
    check events[0].key == "api:alice"
    check events[0].result.allowed
    check events[1].action == sfwaConsume
    check events[2].action == sfwaClear
    check events[2].cleared

  test "in-memory storage enforces key capacity and prunes expired entries":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage(maxKeys = 2).asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    check limiter.allow("alice")
    check limiter.allow("bob")

    expect RateLimitError:
      discard limiter.allow("carol")

    time.advance(initDuration(seconds = 1))
    check limiter.allow("carol")

  test "rejects invalid storage objects":
    expect RateLimitConfigError:
      discard initInMemoryRateLimitStorage(maxKeys = 0)

    expect RateLimitConfigError:
      discard asRateLimitStorage(nil)

    expect RateLimitConfigError:
      discard initStoredFixedWindow(
        prefix = "api",
        limit = 1,
        per = initDuration(seconds = 1),
        storage = RateLimitStorage(),
        timeSource = initManualTimeSource()
      )

  test "default constructor uses a real time source":
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
    let limiter = initStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage
    )

    check limiter.allow("alice")
    check not limiter.allow("alice")
