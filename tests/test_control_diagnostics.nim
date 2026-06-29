import std/[sequtils, unittest]

import flowbrigade

suite "control diagnostics":
  test "empty signals return advice-only empty report":
    let report = analyzeControlSignals(@[])

    check report.mode == "advice-only"
    check report.signalCount == 0
    check report.hints.len == 0

  test "small samples do not produce hints":
    let report = analyzeControlSignals(@[
      failureSignal(),
      failureSignal()
    ])

    check report.signalCount == 2
    check report.failureRate == 1.0
    check report.hints.len == 0

  test "high failure rate suggests inspection and fewer retries":
    let report = analyzeControlSignals(@[
      failureSignal(),
      failureSignal(),
      failureSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal()
    ])

    check report.failureRate == 0.3
    check report.hints.anyIt(it.kind == chkInspectDownstream)
    check report.hints.anyIt(it.kind == chkReduceRetryAttempts)

  test "timeouts count as failures and retry pressure":
    let report = analyzeControlSignals(@[
      timeoutSignal(),
      timeoutSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal()
    ])

    check report.timeoutRate == 0.2
    check report.failureRate == 0.2
    check report.hints.anyIt(it.kind == chkReduceRetryAttempts)

  test "rate-limit pressure suggests tighter inspection":
    let report = analyzeControlSignals(@[
      rateLimitedSignal(),
      rateLimitedSignal(),
      rateLimitedSignal(),
      rateLimitedSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal()
    ])

    check report.rateLimitRate == 0.4
    check report.hints.anyIt(it.kind == chkTightenRateLimit)

  test "bulkhead saturation suggests reducing concurrency":
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

    check report.bulkheadFullRate == 0.3
    check report.hints.anyIt(it.kind == chkReduceConcurrency)

  test "healthy windows can suggest restoring normal settings":
    let report = analyzeControlSignals(@[
      successSignal(10.ms),
      successSignal(20.ms),
      successSignal(30.ms),
      successSignal(40.ms),
      successSignal(50.ms),
      successSignal(60.ms),
      successSignal(70.ms),
      successSignal(80.ms),
      successSignal(90.ms),
      successSignal(100.ms)
    ])

    check report.successRate == 1.0
    check report.averageLatency == 55.ms
    check report.hints.anyIt(it.kind == chkRestoreNormal)

  test "configuration validates thresholds":
    expect ControlDiagnosticsConfigError:
      discard analyzeControlSignals(@[], ControlDiagnosticsConfig(minSignals: 0))

    var config = defaultControlDiagnosticsConfig()
    config.highFailureRate = 1.5
    expect ControlDiagnosticsConfigError:
      discard analyzeControlSignals(@[], config)
