import ./headers
import ./result

type
  RateLimitHeaderMode* = enum
    noRateLimitHeaders,
    standardRateLimitHeaders,
    legacyRateLimitHeaders,
    standardAndLegacyRateLimitHeaders

  HttpLimitDecision* = object
    allowed*: bool
    statusCode*: int
    body*: string
    headers*: seq[RateLimitHeader]
    decision*: RateLimitResult

proc headersFor(
    decision: RateLimitResult;
    mode: RateLimitHeaderMode
): seq[RateLimitHeader] =
  case mode
  of noRateLimitHeaders:
    result = @[]
  of standardRateLimitHeaders:
    result = rateLimitHeaders(decision, includeLegacy = false)
  of legacyRateLimitHeaders:
    var all = rateLimitHeaders(decision, includeLegacy = true)
    for header in all:
      if header.name == "X-RateLimit-Limit" or
          header.name == "X-RateLimit-Remaining" or
          header.name == "X-RateLimit-Reset":
        result.add(header)
  of standardAndLegacyRateLimitHeaders:
    result = rateLimitHeaders(decision, includeLegacy = true)

proc httpLimitDecision*(
    decision: RateLimitResult;
    deniedStatusCode = 429;
    deniedBody = "Too many requests";
    headerMode = standardAndLegacyRateLimitHeaders
): HttpLimitDecision =
  ## Converts a rate-limit decision to framework-neutral HTTP response data.
  ##
  ## Framework packages can translate this object into their own response type.
  let statusCode = if decision.allowed: 200 else: deniedStatusCode
  HttpLimitDecision(
    allowed: decision.allowed,
    statusCode: statusCode,
    body: if decision.allowed: "" else: deniedBody,
    headers: headersFor(decision, headerMode),
    decision: decision
  )
