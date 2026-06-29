import std/[strutils, times]

import ./result

type
  ## HTTP header name/value pair derived from a rate-limit decision.
  RateLimitHeader* = tuple[name: string, value: string]

proc ceilSeconds(duration: Duration): int =
  let nanos = duration.inNanoseconds
  if nanos <= 0:
    return 0
  int((nanos + 999_999_999'i64) div 1_000_000_000'i64)

proc retryAfterSeconds*(decision: RateLimitResult): int =
  ## Returns the Retry-After value in whole seconds.
  ceilSeconds(decision.retryAfter)

proc resetAfterSeconds*(decision: RateLimitResult): int =
  ## Returns the reset delay in whole seconds.
  ##
  ## This is a relative delay, not a Unix timestamp.
  ceilSeconds(decision.resetAfter)

proc rateLimitHeaders*(
    decision: RateLimitResult;
    includeLegacy = true
): seq[RateLimitHeader] =
  ## Builds standard and optional legacy rate-limit headers.
  ##
  ## Denied decisions include `Retry-After`. Legacy `X-RateLimit-*` headers are
  ## included by default for frameworks and clients that still expect them.
  result = @[
    ("RateLimit-Limit", $decision.limit),
    ("RateLimit-Remaining", $decision.remaining),
    ("RateLimit-Reset", $decision.resetAfterSeconds())
  ]

  if not decision.allowed:
    result.add(("Retry-After", $decision.retryAfterSeconds()))

  if includeLegacy:
    result.add(("X-RateLimit-Limit", $decision.limit))
    result.add(("X-RateLimit-Remaining", $decision.remaining))
    result.add(("X-RateLimit-Reset", $decision.resetAfterSeconds()))

proc rateLimitHeadersTable*(
    decision: RateLimitResult;
    includeLegacy = true
): seq[(string, string)] =
  ## Returns rate-limit headers as plain `(name, value)` tuples.
  for header in rateLimitHeaders(decision, includeLegacy):
    result.add((header.name, header.value))

proc formatRateLimitHeaders*(
    decision: RateLimitResult;
    includeLegacy = true
): string =
  ## Formats rate-limit headers as newline-separated `Name: value` lines.
  var lines: seq[string] = @[]
  for header in rateLimitHeaders(decision, includeLegacy):
    lines.add(header.name & ": " & header.value)
  lines.join("\n")
