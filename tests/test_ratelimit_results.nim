import std/[times, unittest]

import flowbrigade/internal/time_source
import flowbrigade/ratelimit

suite "rate limit result API":
  test "token bucket consume returns allowance metadata":
    let time = initManualTimeSource()
    var limiter = initTokenBucket(
      rate = 2,
      per = initDuration(seconds = 1),
      burst = 2,
      timeSource = time
    )

    let first = limiter.consume()
    check first.allowed
    check first.limit == 2
    check first.remaining == 1
    check first.retryAfter == initDuration()

    discard limiter.consume()
    let denied = limiter.consume()
    check not denied.allowed
    check denied.remaining == 0
    check denied.retryAfter == initDuration(milliseconds = 500)

  test "token bucket inspect refills but does not consume tokens":
    let time = initManualTimeSource()
    var limiter = initTokenBucket(
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1,
      timeSource = time
    )

    let preview = limiter.inspect()
    check preview.allowed
    check preview.remaining == 0
    check limiter.allow()
    check not limiter.allow()

  test "fixed window consume returns retry timing on denial":
    let time = initManualTimeSource()
    var limiter = initFixedWindow(
      limit = 2,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    discard limiter.consume(cost = 2)
    let denied = limiter.consume()
    check not denied.allowed
    check denied.limit == 2
    check denied.remaining == 0
    check denied.retryAfter == initDuration(seconds = 1)
    check denied.resetAfter == initDuration(seconds = 1)

    time.advance(initDuration(milliseconds = 400))
    let later = limiter.inspect()
    check not later.allowed
    check later.retryAfter == initDuration(milliseconds = 600)

  test "fixed window inspect does not consume capacity":
    let time = initManualTimeSource()
    var limiter = initFixedWindow(
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    check limiter.inspect().allowed
    check limiter.inspect().allowed
    check limiter.allow()
    check not limiter.allow()

  test "keyed fixed window result tracks keys independently":
    let time = initManualTimeSource()
    var limiter = initKeyedFixedWindow[string](
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    let alice = limiter.consume("alice")
    let bob = limiter.consume("bob")
    let aliceDenied = limiter.consume("alice")

    check alice.allowed
    check bob.allowed
    check not aliceDenied.allowed
    check aliceDenied.retryAfter == initDuration(seconds = 1)

  test "result API rejects invalid costs consistently":
    let time = initManualTimeSource()
    var tokenBucket = initTokenBucket(
      rate = 1,
      per = initDuration(seconds = 1),
      burst = 1,
      timeSource = time
    )
    var fixedWindow = initFixedWindow(
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )
    var keyed = initKeyedFixedWindow[string](
      limit = 1,
      per = initDuration(seconds = 1),
      timeSource = time
    )

    expect RateLimitError:
      discard tokenBucket.inspect(cost = 0)
    expect RateLimitError:
      discard fixedWindow.consume(cost = -1)
    expect RateLimitError:
      discard keyed.inspect("alice", cost = 2)
