import std/times

import flowbrigade

let policy = fixedBackoff(initDuration(milliseconds = 100))

proc sleep(delay: Duration) =
  discard

proc callService(): int =
  42

let result = retry(
  policy = policy,
  maxAttempts = 3,
  sleep = sleep,
  operation = callService
)

doAssert result == 42
