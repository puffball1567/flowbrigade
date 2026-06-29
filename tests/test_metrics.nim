import std/unittest

import flowbrigade

suite "metric event helpers":
  test "converts retry events":
    let event = RetryEvent(
      kind: retrySleeping,
      attempt: 2,
      delay: 150.ms
    )

    let metric = metricEvent(event)

    check metric.name == "flowbrigade.retry.sleeping"
    check metric.value == 1.0
    check ("attempt", "2") in metric.tags

  test "converts circuit breaker events":
    let event = CircuitBreakerEvent(
      kind: circuitOpened,
      state: circuitOpen,
      failures: 3
    )

    let metric = metricEvent(event)

    check metric.name == "flowbrigade.circuit.opened"
    check ("state", "circuitOpen") in metric.tags
    check ("failures", "3") in metric.tags

  test "converts stored limiter audit events":
    let event = StoredFixedWindowAuditEvent(
      action: sfwaConsume,
      key: "api:user:42",
      result: allowedResult(limit = 10, remaining = 9, resetAfter = 1.min)
    )

    let metric = metricEvent(event)

    check metric.name == "flowbrigade.ratelimit.consume"
    check ("key", "api:user:42") in metric.tags
    check ("allowed", "true") in metric.tags
    check ("remaining", "9") in metric.tags

  test "converts clear audit events":
    let event = StoredFixedWindowAuditEvent(
      action: sfwaClear,
      key: "api:user:42",
      cleared: true
    )

    let metric = metricEvent(event)

    check metric.name == "flowbrigade.ratelimit.clear"
    check ("cleared", "true") in metric.tags

  test "converts rate limit decisions":
    let metric = metricEvent(deniedResult(
      limit = 10,
      remaining = 0,
      retryAfter = 5.sec,
      resetAfter = 20.sec
    ))

    check metric.name == "flowbrigade.ratelimit.decision"
    check ("allowed", "false") in metric.tags
    check ("limit", "10") in metric.tags
    check ("remaining", "0") in metric.tags

  test "converts budget decisions":
    let metric = metricEvent(deniedBudgetResult(
      key = "tenant:1",
      limit = 10,
      used = 10,
      cost = 1,
      retryAfter = 5.sec,
      resetAfter = 20.sec
    ))

    check metric.name == "flowbrigade.budget.decision"
    check ("key", "tenant:1") in metric.tags
    check ("allowed", "false") in metric.tags
    check ("limit", "10") in metric.tags
    check ("used", "10") in metric.tags
    check ("remaining", "0") in metric.tags
