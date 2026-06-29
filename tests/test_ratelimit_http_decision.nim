import std/[times, unittest]

import flowbrigade/ratelimit

suite "HTTP rate-limit decision":
  test "builds allowed HTTP decision":
    let decision = allowedResult(
      limit = 10,
      remaining = 9,
      resetAfter = initDuration(minutes = 1)
    )

    let http = httpLimitDecision(decision)

    check http.allowed
    check http.statusCode == 200
    check http.body == ""
    check ("RateLimit-Limit", "10") in http.headers

  test "builds denied HTTP decision":
    let decision = deniedResult(
      limit = 10,
      remaining = 0,
      retryAfter = initDuration(seconds = 30),
      resetAfter = initDuration(minutes = 1)
    )

    let http = httpLimitDecision(
      decision,
      deniedStatusCode = 503,
      deniedBody = "slow down",
      headerMode = standardRateLimitHeaders
    )

    check not http.allowed
    check http.statusCode == 503
    check http.body == "slow down"
    check ("Retry-After", "30") in http.headers
    check ("X-RateLimit-Limit", "10") notin http.headers

  test "can omit headers":
    let decision = allowedResult(
      limit = 10,
      remaining = 9,
      resetAfter = initDuration(minutes = 1)
    )

    check httpLimitDecision(decision, headerMode = noRateLimitHeaders).headers.len == 0

  test "can emit only legacy headers":
    let decision = allowedResult(
      limit = 10,
      remaining = 9,
      resetAfter = initDuration(minutes = 1)
    )

    let http = httpLimitDecision(decision, headerMode = legacyRateLimitHeaders)

    check ("X-RateLimit-Limit", "10") in http.headers
    check ("RateLimit-Limit", "10") notin http.headers
