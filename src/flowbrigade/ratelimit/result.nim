import std/times

type
  RateLimitResult* = object
    allowed*: bool
    limit*: int
    remaining*: int
    retryAfter*: Duration
    resetAfter*: Duration

proc allowedResult*(limit, remaining: int; resetAfter: Duration): RateLimitResult =
  RateLimitResult(
    allowed: true,
    limit: limit,
    remaining: max(0, remaining),
    retryAfter: initDuration(),
    resetAfter: resetAfter
  )

proc deniedResult*(
    limit, remaining: int;
    retryAfter, resetAfter: Duration
): RateLimitResult =
  RateLimitResult(
    allowed: false,
    limit: limit,
    remaining: max(0, remaining),
    retryAfter: retryAfter,
    resetAfter: resetAfter
  )
