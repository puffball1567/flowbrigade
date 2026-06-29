import std/[strutils, times, unittest]

import flowbrigade/ratelimit

suite "rate limit HTTP headers":
  test "formats allowed result headers":
    let decision = allowedResult(
      limit = 10,
      remaining = 4,
      resetAfter = initDuration(milliseconds = 1500)
    )

    let headers = decision.rateLimitHeaders()
    check ("RateLimit-Limit", "10") in headers
    check ("RateLimit-Remaining", "4") in headers
    check ("RateLimit-Reset", "2") in headers
    check ("X-RateLimit-Limit", "10") in headers

  test "formats denied result with retry after":
    let decision = deniedResult(
      limit = 10,
      remaining = 0,
      retryAfter = initDuration(milliseconds = 250),
      resetAfter = initDuration(seconds = 1)
    )

    let headers = decision.rateLimitHeaders(includeLegacy = false)
    check ("Retry-After", "1") in headers
    check ("RateLimit-Reset", "1") in headers
    check ("X-RateLimit-Limit", "10") notin headers

  test "formats headers as text":
    let decision = deniedResult(
      limit = 1,
      remaining = 0,
      retryAfter = initDuration(seconds = 2),
      resetAfter = initDuration(seconds = 2)
    )

    let text = decision.formatRateLimitHeaders(includeLegacy = false)
    check text.contains("RateLimit-Limit: 1")
    check text.contains("Retry-After: 2")
