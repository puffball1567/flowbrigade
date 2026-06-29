import std/times

import flowbrigade

var attempts = 0
var plannedSleeps: seq[Duration] = @[]

let policy = expBackoff(
  initial = 100.ms,
  factor = 2.0,
  maxDelay = 1.sec
)

let value = retry(
  policy = policy,
  maxAttempts = 3,
  sleep = proc(delay: Duration) =
    plannedSleeps.add(delay),
  operation = proc(): string =
    inc attempts
    if attempts < 3:
      raise newException(IOError, "temporary failure")
    "ok"
)

doAssert value == "ok"
doAssert plannedSleeps == @[100.ms, 200.ms]

echo "result=", value
echo "attempts=", attempts
