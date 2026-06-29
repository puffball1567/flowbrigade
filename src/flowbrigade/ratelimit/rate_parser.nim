import std/[parseutils, strutils, times]

import ../durations
import ./errors

type
  RateLimitRate* = object
    limit*: int
    per*: Duration

proc parsePeriod(value: string): Duration =
  case value
  of "s", "S": 1.sec
  of "m", "M": 1.min
  of "h", "H": 1.hr
  of "d", "D": 1.day
  else:
    parseDuration(value)

proc parseRateLimitRate*(value: string): RateLimitRate =
  ## Parses compact rate strings such as `100/m`, `5-S`, and `1000/1h`.
  ##
  ## This helper is intentionally small. Config file parsing remains the
  ## caller's responsibility; FlowBrigade only parses the rate expression.
  let input = value.strip()
  if input.len == 0:
    raise newException(RateLimitConfigError, "rate must not be empty")

  let separator =
    if input.contains("/"): "/"
    elif input.contains("-"): "-"
    else: ""
  if separator.len == 0:
    raise newException(RateLimitConfigError, "rate must contain '/' or '-'")

  let parts = input.split(separator)
  if parts.len != 2:
    raise newException(RateLimitConfigError, "rate must contain one separator")

  let rawLimit = parts[0].strip()
  let rawPeriod = parts[1].strip()
  if rawLimit.len == 0 or rawPeriod.len == 0:
    raise newException(RateLimitConfigError, "rate limit and period are required")

  var limit = 0
  var parsed = 0
  if parseInt(rawLimit, limit, 0) != rawLimit.len:
    raise newException(RateLimitConfigError, "rate limit must be an integer")
  if limit < 0:
    raise newException(RateLimitConfigError, "rate limit must not be negative")

  let period = parsePeriod(rawPeriod)
  if period <= initDuration():
    raise newException(RateLimitConfigError, "rate period must be positive")

  parsed = limit
  RateLimitRate(limit: parsed, per: period)
