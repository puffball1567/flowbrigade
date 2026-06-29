import std/[strutils, times]

import pkg/flowbrigade
import pkg/flowbrigade/internal/time_source

type
  Response = object
    status: int
    body: string

proc primary(): Response =
  raise newException(IOError, "primary unavailable")

proc secondary(): Response =
  Response(status: 200, body: "ok")

let time = initManualTimeSource()
let deadline = initDeadline(after = 2.sec, timeSource = time)
let policy = apiAbuseProtectionPolicy(
  perIdentityLimit = 2,
  perIdentityWindow = 1.min,
  globalRate = 10,
  globalPer = 1.sec,
  globalBurst = 10
)

let key = "api:tenant:42"
let decision = policy.consume(key)
doAssert decision.allowed

let downstreamBudget = deadline.clamp(1500.ms)
doAssert downstreamBudget == 1500.ms

let result = tryInOrder([
  fallbackProvider("primary", primary),
  fallbackProvider("secondary", secondary)
])

doAssert result.provider == "secondary"
doAssert result.value.status == 200
doAssert result.value.body == "ok"

let events = @[
  metricEvent(decision),
  MetricEvent(
    name: "flowbrigade.example.deadline_remaining_ms",
    value: float(deadline.remaining().inNanoseconds) / 1_000_000.0
  )
]

let jsonLines = events.toJsonLines()
let prometheusText = events.toPrometheusText()

doAssert jsonLines.contains("flowbrigade.ratelimit.decision")
doAssert prometheusText.contains("flowbrigade_example_deadline_remaining_ms")
