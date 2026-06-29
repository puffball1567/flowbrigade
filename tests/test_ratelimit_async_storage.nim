import std/[asyncdispatch, times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/ratelimit

suite "async rate limit storage interface":
  test "async stored fixed window shares state through wrapped storage":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage().asAsyncRateLimitStorage()
    let limiter = initAsyncStoredFixedWindow(
      prefix = "api",
      limit = 2,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    check waitFor limiter.allow("alice")
    check waitFor limiter.allow("alice")
    check not waitFor limiter.allow("alice")

  test "async inspect does not consume capacity":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage().asAsyncRateLimitStorage()
    let limiter = initAsyncStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    check (waitFor limiter.inspect("alice")).allowed
    check (waitFor limiter.inspect("alice")).allowed
    check waitFor limiter.allow("alice")
    check not waitFor limiter.allow("alice")

  test "async stored fixed window resets after the window expires":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage().asAsyncRateLimitStorage()
    let limiter = initAsyncStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    check waitFor limiter.allow("alice")
    check not waitFor limiter.allow("alice")

    time.advance(initDuration(seconds = 1))
    check waitFor limiter.allow("alice")

  test "async stored fixed window returns metadata and can clear":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage().asAsyncRateLimitStorage()
    let limiter = initAsyncStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    let allowed = waitFor limiter.consume("alice")
    check allowed.allowed
    check allowed.remaining == 0

    time.advance(initDuration(milliseconds = 250))
    let denied = waitFor limiter.consume("alice")
    check not denied.allowed
    check denied.retryAfter == initDuration(milliseconds = 750)

    check waitFor limiter.clear("alice")
    check waitFor limiter.allow("alice")

  test "async stored fixed window emits audit events":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage().asAsyncRateLimitStorage()
    var events: seq[StoredFixedWindowAuditEvent] = @[]
    let limiter = initAsyncStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time,
      audit = proc(event: StoredFixedWindowAuditEvent) =
        events.add(event)
    )

    discard waitFor limiter.inspect("alice")
    discard waitFor limiter.consume("alice")
    discard waitFor limiter.clear("alice")

    check events.len == 3
    check events[0].action == sfwaInspect
    check events[0].key == "api:alice"
    check events[1].action == sfwaConsume
    check events[2].action == sfwaClear
    check events[2].cleared

  test "async stored fixed window rejects invalid configuration and input":
    let time = initManualTimeSource()
    let storage = initInMemoryRateLimitStorage().asRateLimitStorage().asAsyncRateLimitStorage()

    expect RateLimitConfigError:
      discard initAsyncStoredFixedWindow(
        prefix = "",
        limit = 1,
        per = initDuration(seconds = 1),
        storage = storage,
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initAsyncStoredFixedWindow(
        prefix = "api",
        limit = 0,
        per = initDuration(seconds = 1),
        storage = storage,
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initAsyncStoredFixedWindow(
        prefix = "api",
        limit = 1,
        per = initDuration(),
        storage = storage,
        timeSource = time
      )

    expect RateLimitConfigError:
      discard initAsyncStoredFixedWindow(
        prefix = "api",
        limit = 1,
        per = initDuration(seconds = 1),
        storage = AsyncRateLimitStorage(),
        timeSource = time
      )

    let limiter = initAsyncStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time,
      maxKeyLength = 5
    )

    expect RateLimitError:
      discard waitFor limiter.allow("")
    expect RateLimitError:
      discard waitFor limiter.allow("   ")
    expect RateLimitError:
      discard waitFor limiter.allow("alice\Lbob")
    expect RateLimitError:
      discard waitFor limiter.allow("charlie")
    expect RateLimitError:
      discard waitFor limiter.inspect("alice", cost = 0)
    expect RateLimitError:
      discard waitFor limiter.consume("alice", cost = 2)

  test "custom async storage callbacks are awaited":
    let time = initManualTimeSource()
    var consumed = false
    let storage = AsyncRateLimitStorage(
      inspectFixedWindow: proc(
        key: string;
        limit: int;
        per: Duration;
        cost: int;
        current: Duration
      ): Future[RateLimitResult] {.async.} =
        await sleepAsync(1)
        allowedResult(limit = limit, remaining = limit - cost, resetAfter = per),
      consumeFixedWindow: proc(
        key: string;
        limit: int;
        per: Duration;
        cost: int;
        current: Duration
      ): Future[RateLimitResult] {.async.} =
        await sleepAsync(1)
        consumed = true
        allowedResult(limit = limit, remaining = limit - cost, resetAfter = per),
      clearFixedWindow: proc(key: string): Future[bool] {.async.} =
        await sleepAsync(1)
        true
    )
    let limiter = initAsyncStoredFixedWindow(
      prefix = "api",
      limit = 1,
      per = initDuration(seconds = 1),
      storage = storage,
      timeSource = time
    )

    check waitFor limiter.allow("alice")
    check consumed
    check waitFor limiter.clear("alice")
