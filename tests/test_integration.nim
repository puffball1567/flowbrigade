import std/unittest

import flowbrigade

suite "integration":
  test "reports FlowCaptain-facing capabilities":
    let capabilities = flowBrigadeCapabilities()

    check capabilities.hasCapability(fbckRateLimit)
    check capabilities.hasCapability(fbckBulkhead)
    check capabilities.hasCapability(fbckControlDiagnostics)

  test "validates integration plan and policies without raising":
    var registry = initLimiterRegistry()
    registry.addLimiter("main", tokenBucketDefinition(10, 1.sec, 10))
    let policy = initFlowPolicy(
      fpkWorkerBackpressure,
      "worker",
      "main",
      registry,
      bulkheadCapacity = 4
    )

    let report = validate(initFlowBrigadePlan(
      "captain",
      requiredCapabilities = [fbckRateLimit, fbckBulkhead],
      policies = [policy]
    ))

    check report.ok
    check report.errors.len == 0
    check report.policyReports.len == 1
    check report.policyReports[0].valid

  test "returns plan validation errors as data":
    let report = validate(initFlowBrigadePlan(""))

    check not report.ok
    check report.errors == @["plan name is required"]
