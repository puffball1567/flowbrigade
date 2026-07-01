import std/times

import ./budget
import ./circuit_breaker
import ./ratelimit
import ./retry
import ./retry_allowance

type
  MetricTag* = tuple[key: string, value: string]

  MetricEvent* = object
    name*: string
    tags*: seq[MetricTag]
    value*: float

proc durationSeconds(value: Duration): float =
  float(value.inNanoseconds) / 1_000_000_000.0

proc retryMetricName(kind: RetryEventKind): string =
  case kind
  of retryAttemptFailed: "flowbrigade.retry.attempt_failed"
  of retrySleeping: "flowbrigade.retry.sleeping"
  of retryExhausted: "flowbrigade.retry.exhausted"
  of retrySucceeded: "flowbrigade.retry.succeeded"

proc circuitMetricName(kind: CircuitBreakerEventKind): string =
  case kind
  of circuitAllowed: "flowbrigade.circuit.allowed"
  of circuitBlocked: "flowbrigade.circuit.blocked"
  of circuitOpened: "flowbrigade.circuit.opened"
  of circuitHalfOpened: "flowbrigade.circuit.half_opened"
  of circuitClosedAfterSuccess: "flowbrigade.circuit.closed_after_success"

proc storedActionMetricName(action: StoredFixedWindowAction): string =
  case action
  of sfwaInspect: "flowbrigade.ratelimit.inspect"
  of sfwaConsume: "flowbrigade.ratelimit.consume"
  of sfwaClear: "flowbrigade.ratelimit.clear"

proc budgetMetricName(kind: BudgetEventKind): string =
  case kind
  of budgetInspect: "flowbrigade.budget.inspect"
  of budgetConsume: "flowbrigade.budget.consume"
  of budgetRefund: "flowbrigade.budget.refund"
  of budgetReset: "flowbrigade.budget.reset"

proc retryAllowanceMetricName(kind: RetryAllowanceEventKind): string =
  case kind
  of retryAllowanceOriginal: "flowbrigade.retry_allowance.original"
  of retryAllowanceInspect: "flowbrigade.retry_allowance.inspect"
  of retryAllowanceConsume: "flowbrigade.retry_allowance.consume"
  of retryAllowanceReset: "flowbrigade.retry_allowance.reset"

proc metricEvent*(event: RetryEvent): MetricEvent =
  result = MetricEvent(
    name: retryMetricName(event.kind),
    value: 1.0,
    tags: @[
      ("attempt", $event.attempt)
    ]
  )
  if event.delay > initDuration():
    result.tags.add(("delay_seconds", $durationSeconds(event.delay)))

proc metricEvent*(event: CircuitBreakerEvent): MetricEvent =
  MetricEvent(
    name: circuitMetricName(event.kind),
    value: 1.0,
    tags: @[
      ("state", $event.state),
      ("failures", $event.failures)
    ]
  )

proc metricEvent*(event: StoredFixedWindowAuditEvent): MetricEvent =
  result = MetricEvent(
    name: storedActionMetricName(event.action),
    value: 1.0,
    tags: @[
      ("key", event.key)
    ]
  )
  case event.action
  of sfwaInspect, sfwaConsume:
    result.tags.add(("allowed", $event.result.allowed))
    result.tags.add(("remaining", $event.result.remaining))
  of sfwaClear:
    result.tags.add(("cleared", $event.cleared))

proc metricEvent*(event: BudgetEvent): MetricEvent =
  result = MetricEvent(
    name: budgetMetricName(event.kind),
    value: 1.0,
    tags: @[
      ("key", event.key),
      ("amount", $event.amount)
    ]
  )
  if event.result.key.len > 0:
    result.tags.add(("allowed", $event.result.allowed))
    result.tags.add(("limit", $event.result.limit))
    result.tags.add(("used", $event.result.used))
    result.tags.add(("remaining", $event.result.remaining))

proc metricEvent*(decision: BudgetResult): MetricEvent =
  result = MetricEvent(
    name: "flowbrigade.budget.decision",
    value: 1.0,
    tags: @[
      ("key", decision.key),
      ("allowed", $decision.allowed),
      ("limit", $decision.limit),
      ("used", $decision.used),
      ("remaining", $decision.remaining),
      ("cost", $decision.cost)
    ]
  )
  if decision.retryAfter > initDuration():
    result.tags.add(("retry_after_seconds", $durationSeconds(decision.retryAfter)))
  if decision.resetAfter > initDuration():
    result.tags.add(("reset_after_seconds", $durationSeconds(decision.resetAfter)))

proc metricEvent*(event: RetryAllowanceEvent): MetricEvent =
  result = MetricEvent(
    name: retryAllowanceMetricName(event.kind),
    value: 1.0,
    tags: @[
      ("key", event.key),
      ("amount", $event.amount)
    ]
  )
  if event.result.key.len > 0:
    result.tags.add(("allowed", $event.result.allowed))
    result.tags.add(("limit", $event.result.limit))
    result.tags.add(("originals", $event.result.originals))
    result.tags.add(("retries", $event.result.retries))
    result.tags.add(("remaining", $event.result.remaining))

proc metricEvent*(decision: RetryAllowanceResult): MetricEvent =
  result = MetricEvent(
    name: "flowbrigade.retry_allowance.decision",
    value: 1.0,
    tags: @[
      ("key", decision.key),
      ("allowed", $decision.allowed),
      ("limit", $decision.limit),
      ("originals", $decision.originals),
      ("retries", $decision.retries),
      ("remaining", $decision.remaining),
      ("cost", $decision.cost)
    ]
  )
  if decision.retryAfter > initDuration():
    result.tags.add(("retry_after_seconds", $durationSeconds(decision.retryAfter)))
  if decision.resetAfter > initDuration():
    result.tags.add(("reset_after_seconds", $durationSeconds(decision.resetAfter)))

proc metricEvent*(decision: RateLimitResult): MetricEvent =
  result = MetricEvent(
    name: "flowbrigade.ratelimit.decision",
    value: 1.0,
    tags: @[
      ("allowed", $decision.allowed),
      ("limit", $decision.limit),
      ("remaining", $decision.remaining)
    ]
  )
  if decision.retryAfter > initDuration():
    result.tags.add(("retry_after_seconds", $durationSeconds(decision.retryAfter)))
  if decision.resetAfter > initDuration():
    result.tags.add(("reset_after_seconds", $durationSeconds(decision.resetAfter)))
