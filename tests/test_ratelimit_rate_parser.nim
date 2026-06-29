import std/[times, unittest]

import flowbrigade/ratelimit

suite "rate limit rate parser":
  test "parses slash shorthand":
    let rate = parseRateLimitRate("100/m")

    check rate.limit == 100
    check rate.per == initDuration(minutes = 1)

  test "parses dash shorthand":
    let rate = parseRateLimitRate("5-S")

    check rate.limit == 5
    check rate.per == initDuration(seconds = 1)

  test "parses duration period":
    let rate = parseRateLimitRate("1000/1h30m")

    check rate.limit == 1000
    check rate.per == initDuration(hours = 1, minutes = 30)

  test "trims whitespace":
    let rate = parseRateLimitRate(" 10 / 1m ")

    check rate.limit == 10
    check rate.per == initDuration(minutes = 1)

  test "rejects malformed rates":
    expect RateLimitConfigError:
      discard parseRateLimitRate("")
    expect RateLimitConfigError:
      discard parseRateLimitRate("100")
    expect RateLimitConfigError:
      discard parseRateLimitRate("100/m/s")
    expect RateLimitConfigError:
      discard parseRateLimitRate("many/m")
    expect RateLimitConfigError:
      discard parseRateLimitRate("-1/m")
    expect RateLimitConfigError:
      discard parseRateLimitRate("1/0s")
