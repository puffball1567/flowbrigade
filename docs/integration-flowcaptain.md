# FlowCaptain Integration

FlowBrigade can be embedded by FlowCaptain as the flow-control component.

## Recommended Boundary

Use `FlowBrigadePlan` during startup or configuration loading:

```nim
import flowbrigade

let plan = initFlowBrigadePlan(
  "captain",
  requiredCapabilities = [fbckRateLimit, fbckBulkhead, fbckControlDiagnostics],
  policies = policies
)

let report = validate(plan)
if not report.ok:
  reject(report.errors)
```

This boundary is intentionally diagnostic. Runtime control should continue to
use the focused FlowBrigade APIs directly: rate limiters, bulkheads, lock
leases, budgets, retries, circuit breakers, and diagnostics.

## Why This Shape

FlowCaptain should be able to check that a selected deployment has the control
features it expects without consuming limiter state or relying on exception
control flow. `FlowBrigadePlanReport` returns capabilities, policy validation
reports, and errors as data.
