import ./result

type
  RateLimitExceededError* = object of CatchableError
    decision*: RateLimitResult

proc newRateLimitExceededError*(
    decision: RateLimitResult;
    message = "rate limit exceeded"
): ref RateLimitExceededError =
  new(result)
  result.msg = message
  result.decision = decision

proc raiseIfDenied*(decision: RateLimitResult) =
  if not decision.allowed:
    raise newRateLimitExceededError(decision)

proc remainingOrRaise*(decision: RateLimitResult): int =
  decision.raiseIfDenied()
  decision.remaining
