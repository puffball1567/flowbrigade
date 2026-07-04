import ./policy

type
  FlowBrigadeCapabilityKind* = enum
    fbckBackoff,
    fbckRetry,
    fbckRateLimit,
    fbckKeyedRateLimit,
    fbckCircuitBreaker,
    fbckBulkhead,
    fbckLockLease,
    fbckBudget,
    fbckTimeoutDeadline,
    fbckThrottleDebounce,
    fbckFallback,
    fbckObservability,
    fbckControlDiagnostics

  FlowBrigadeCapability* = object
    kind*: FlowBrigadeCapabilityKind
    stable*: bool
    description*: string

  FlowBrigadePlan* = object
    name*: string
    requiredCapabilities*: seq[FlowBrigadeCapabilityKind]
    policies*: seq[FlowPolicy]

  FlowBrigadePlanReport* = object
    ok*: bool
    name*: string
    capabilities*: seq[FlowBrigadeCapability]
    policyReports*: seq[FlowPolicyValidationReport]
    errors*: seq[string]

proc flowBrigadeCapabilities*(): seq[FlowBrigadeCapability] =
  @[
    FlowBrigadeCapability(kind: fbckBackoff, stable: true,
      description: "retry delay policies"),
    FlowBrigadeCapability(kind: fbckRetry, stable: true,
      description: "sync and async retry helpers"),
    FlowBrigadeCapability(kind: fbckRateLimit, stable: true,
      description: "token bucket, fixed window, sliding window, and GCRA limiters"),
    FlowBrigadeCapability(kind: fbckKeyedRateLimit, stable: true,
      description: "per-key rate limiters for identities, tenants, and resources"),
    FlowBrigadeCapability(kind: fbckCircuitBreaker, stable: true,
      description: "failure-aware circuit breaker"),
    FlowBrigadeCapability(kind: fbckBulkhead, stable: true,
      description: "concurrency isolation"),
    FlowBrigadeCapability(kind: fbckLockLease, stable: true,
      description: "in-memory lock and lease primitives"),
    FlowBrigadeCapability(kind: fbckBudget, stable: true,
      description: "budget and quota accounting"),
    FlowBrigadeCapability(kind: fbckTimeoutDeadline, stable: true,
      description: "timeout and deadline helpers"),
    FlowBrigadeCapability(kind: fbckThrottleDebounce, stable: true,
      description: "throttle and debounce helpers"),
    FlowBrigadeCapability(kind: fbckFallback, stable: true,
      description: "fallback provider selection"),
    FlowBrigadeCapability(kind: fbckObservability, stable: true,
      description: "machine-readable control results"),
    FlowBrigadeCapability(kind: fbckControlDiagnostics, stable: true,
      description: "advice-only diagnostics over control signals")
  ]

proc hasCapability*(capabilities: openArray[FlowBrigadeCapability];
    kind: FlowBrigadeCapabilityKind): bool =
  for capability in capabilities:
    if capability.kind == kind:
      return true

proc initFlowBrigadePlan*(name: string;
    requiredCapabilities: openArray[FlowBrigadeCapabilityKind] = [];
    policies: openArray[FlowPolicy] = []): FlowBrigadePlan =
  FlowBrigadePlan(
    name: name,
    requiredCapabilities: @requiredCapabilities,
    policies: @policies
  )

proc validate*(plan: FlowBrigadePlan): FlowBrigadePlanReport =
  result = FlowBrigadePlanReport(
    ok: true,
    name: plan.name,
    capabilities: flowBrigadeCapabilities()
  )

  if plan.name.len == 0:
    result.ok = false
    result.errors.add("plan name is required")

  for required in plan.requiredCapabilities:
    if not result.capabilities.hasCapability(required):
      result.ok = false
      result.errors.add("missing capability: " & $required)

  for policy in plan.policies:
    let report = policy.validate()
    result.policyReports.add(report)
    if not report.valid:
      result.ok = false
      for issue in report.issues:
        result.errors.add("policy " & report.policyName & ": " & issue.path & ": " & issue.message)
