import std/times

type
  ControlDiagnosticsConfigError* = object of ValueError

  ControlSignalKind* = enum
    cskSuccess,
    cskFailure,
    cskTimeout,
    cskRateLimited,
    cskCircuitOpen,
    cskBulkheadFull

  ControlHintKind* = enum
    chkInspectDownstream,
    chkReduceRetryAttempts,
    chkTightenRateLimit,
    chkReduceConcurrency,
    chkIncreaseCapacity,
    chkRestoreNormal

  ControlSignal* = object
    kind*: ControlSignalKind
    latency*: Duration
    key*: string

  ControlDiagnosticsConfig* = object
    minSignals*: int
    highFailureRate*: float
    highTimeoutRate*: float
    highRateLimitRate*: float
    highBulkheadFullRate*: float
    highCircuitOpenRate*: float
    lowProblemRate*: float

  ControlHint* = object
    kind*: ControlHintKind
    confidence*: float
    reason*: string

  ControlReport* = object
    mode*: string
    signalCount*: int
    successRate*: float
    failureRate*: float
    timeoutRate*: float
    rateLimitRate*: float
    circuitOpenRate*: float
    bulkheadFullRate*: float
    averageLatency*: Duration
    hints*: seq[ControlHint]

proc defaultControlDiagnosticsConfig*(): ControlDiagnosticsConfig =
  ControlDiagnosticsConfig(
    minSignals: 10,
    highFailureRate: 0.20,
    highTimeoutRate: 0.10,
    highRateLimitRate: 0.30,
    highBulkheadFullRate: 0.20,
    highCircuitOpenRate: 0.10,
    lowProblemRate: 0.02
  )

proc validateConfig(config: ControlDiagnosticsConfig) =
  if config.minSignals <= 0:
    raise newException(ControlDiagnosticsConfigError, "minSignals must be positive")
  for item in [
    ("highFailureRate", config.highFailureRate),
    ("highTimeoutRate", config.highTimeoutRate),
    ("highRateLimitRate", config.highRateLimitRate),
    ("highBulkheadFullRate", config.highBulkheadFullRate),
    ("highCircuitOpenRate", config.highCircuitOpenRate),
    ("lowProblemRate", config.lowProblemRate)
  ]:
    if item[1] < 0.0 or item[1] > 1.0:
      raise newException(ControlDiagnosticsConfigError, item[0] & " must be between 0 and 1")

proc clamp01(value: float): float =
  min(1.0, max(0.0, value))

proc ratio(count, total: int): float =
  if total <= 0:
    0.0
  else:
    count.float / total.float

proc controlSignal*(kind: ControlSignalKind; latency = initDuration(); key = ""): ControlSignal =
  ControlSignal(kind: kind, latency: latency, key: key)

proc successSignal*(latency = initDuration(); key = ""): ControlSignal =
  controlSignal(cskSuccess, latency, key)

proc failureSignal*(latency = initDuration(); key = ""): ControlSignal =
  controlSignal(cskFailure, latency, key)

proc timeoutSignal*(latency = initDuration(); key = ""): ControlSignal =
  controlSignal(cskTimeout, latency, key)

proc rateLimitedSignal*(key = ""): ControlSignal =
  controlSignal(cskRateLimited, key = key)

proc circuitOpenSignal*(key = ""): ControlSignal =
  controlSignal(cskCircuitOpen, key = key)

proc bulkheadFullSignal*(key = ""): ControlSignal =
  controlSignal(cskBulkheadFull, key = key)

proc addHint(report: var ControlReport; kind: ControlHintKind; confidence: float; reason: string) =
  report.hints.add ControlHint(
    kind: kind,
    confidence: clamp01(confidence),
    reason: reason
  )

proc analyzeControlSignals*(
    signals: openArray[ControlSignal];
    config = defaultControlDiagnosticsConfig()
): ControlReport =
  validateConfig(config)
  result.mode = "advice-only"
  result.signalCount = signals.len
  if signals.len == 0:
    return

  var successes = 0
  var failures = 0
  var timeouts = 0
  var rateLimited = 0
  var circuitOpen = 0
  var bulkheadFull = 0
  var latencyTotal = initDuration()
  var latencyCount = 0

  for signal in signals:
    case signal.kind
    of cskSuccess:
      inc successes
    of cskFailure:
      inc failures
    of cskTimeout:
      inc timeouts
    of cskRateLimited:
      inc rateLimited
    of cskCircuitOpen:
      inc circuitOpen
    of cskBulkheadFull:
      inc bulkheadFull
    if signal.latency > initDuration():
      latencyTotal += signal.latency
      inc latencyCount

  result.successRate = ratio(successes, signals.len)
  result.failureRate = ratio(failures + timeouts, signals.len)
  result.timeoutRate = ratio(timeouts, signals.len)
  result.rateLimitRate = ratio(rateLimited, signals.len)
  result.circuitOpenRate = ratio(circuitOpen, signals.len)
  result.bulkheadFullRate = ratio(bulkheadFull, signals.len)
  if latencyCount > 0:
    result.averageLatency = initDuration(
      nanoseconds = latencyTotal.inNanoseconds div latencyCount
    )

  if signals.len < config.minSignals:
    return

  if result.failureRate >= config.highFailureRate:
    result.addHint(
      chkInspectDownstream,
      result.failureRate,
      "failure rate is high; inspect the dependency before increasing retries"
    )
    result.addHint(
      chkReduceRetryAttempts,
      result.failureRate,
      "high failure rate can make retries amplify load"
    )

  if result.timeoutRate >= config.highTimeoutRate:
    result.addHint(
      chkReduceRetryAttempts,
      result.timeoutRate,
      "timeouts are frequent; shorter retry chains may reduce queued work"
    )

  if result.rateLimitRate >= config.highRateLimitRate:
    result.addHint(
      chkTightenRateLimit,
      result.rateLimitRate,
      "rate-limit denials are frequent; inspect abusive or oversized callers"
    )

  if result.bulkheadFullRate >= config.highBulkheadFullRate:
    result.addHint(
      chkReduceConcurrency,
      result.bulkheadFullRate,
      "bulkhead saturation is high; reduce intake or split capacity"
    )

  if result.circuitOpenRate >= config.highCircuitOpenRate:
    result.addHint(
      chkInspectDownstream,
      result.circuitOpenRate,
      "circuit-open signals are frequent; dependency health needs inspection"
    )

  let problemRate =
    result.failureRate + result.rateLimitRate + result.circuitOpenRate + result.bulkheadFullRate
  if problemRate <= config.lowProblemRate and result.successRate > 0.0:
    result.addHint(
      chkRestoreNormal,
      1.0 - problemRate,
      "recent control signals are mostly healthy; normal settings may be acceptable"
    )
