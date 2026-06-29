import std/strutils

import flowbrigade

let decision = deniedResult(
  limit = 10,
  remaining = 0,
  retryAfter = 5.sec,
  resetAfter = 1.min
)

let metric = metricEvent(decision)

let jsonLine = metric.toJsonLine()
let textLine = metric.toPrometheusLine()

doAssert jsonLine.contains("flowbrigade.ratelimit.decision")
doAssert textLine.startsWith("flowbrigade_ratelimit_decision")

let report = analyzeControlSignals(@[
  bulkheadFullSignal(),
  bulkheadFullSignal(),
  bulkheadFullSignal(),
  successSignal(),
  successSignal(),
  successSignal(),
  successSignal(),
  successSignal(),
  successSignal(),
  successSignal()
])

let reportJson = report.controlReportToJsonLine()
let reportMetrics = report.controlReportMetrics()

doAssert reportJson.contains("flowbrigade.control_report.v1")
doAssert reportMetrics.len > 0
