# Batch and workflow runtimes

FlowBrigade is not a workflow management system like Nextflow. It does not
model DAGs, channels, task scheduling, resume/restart state, process isolation,
container execution, or pipeline syntax.

It is useful one layer lower: the worker or runtime code that executes a task.
If you are building a Nim batch runner, workflow engine, queue worker, or
pipeline service, FlowBrigade can wrap each task execution with operational
controls.

## Where it fits

| Workflow concern | FlowBrigade role |
| --- | --- |
| DAG construction | out of scope |
| Task scheduling | out of scope |
| Retry transient task failures | `retry` with bounded backoff |
| Per-task or workflow time budget | `Deadline`, `childDeadline`, `clamp` |
| Limit calls to shared services | `TokenBucket`, `FixedWindow`, `StoredFixedWindow` |
| Per-tenant or per-project allowance | `BudgetLedger` |
| Limit local worker concurrency | `Bulkhead` |
| Stop calling a failing dependency | `CircuitBreaker` |
| Protect a named critical section | `LockStore` |
| Export runtime control signals | `MetricEvent`, `toJsonLines`, `toPrometheusText` |

The boundary is intentional. A workflow tool should own orchestration and task
lifecycle. FlowBrigade can own small, testable decisions around whether a task
should run now, how it should retry, and what runtime metadata should be
emitted.

## Minimal worker wrapper

Start by wrapping one task execution function. This example uses:

- a worker backpressure policy for task ingress
- a budget ledger for tenant quota
- a circuit breaker for a fragile dependency
- a bulkhead for local concurrency
- a deadline for the workflow time budget
- metric events for observability

```nim
import std/[strutils, times]

import pkg/flowbrigade

type
  WorkflowTask = object
    id: string
    tenant: string
    cost: int64
    payload: string

  TaskOutcome = object
    accepted: bool
    output: string
    metrics: seq[MetricEvent]

let workerPolicy = workerBackpressurePolicy(
  name = "batch_worker",
  rate = 20,
  per = 1.sec,
  burst = 40,
  concurrency = 2,
  failureThreshold = 3,
  resetAfter = 30.sec
)

var quota = initBudgetLedger(dailyQuotaConfig(10_000))
var breaker = initCircuitBreaker(workerPolicy)
var bulkhead = initBulkhead(workerPolicy)

proc execute(task: WorkflowTask; timeBudget: Duration): string =
  if timeBudget <= 0.ms:
    raise newException(ValueError, "task has no remaining time budget")
  if task.payload.len == 0:
    raise newException(ValueError, "empty payload")
  "processed:" & task.id & ":" & task.payload.toUpperAscii()

proc runTask(task: WorkflowTask; workflowBudget: Deadline): TaskOutcome =
  let taskKey = rateLimitKey(["tenant", task.tenant, "task", task.id])
  var events: seq[MetricEvent] = @[]

  let quotaDecision = quota.consume(task.tenant, cost = task.cost)
  events.add(metricEvent(quotaDecision))
  if not quotaDecision.allowed:
    return TaskOutcome(accepted: false, output: "quota exceeded", metrics: events)

  let flowDecision = workerPolicy.consume(taskKey)
  events.add(metricEvent(flowDecision))
  if not flowDecision.allowed:
    return TaskOutcome(accepted: false, output: "worker is backpressured", metrics: events)

  if not breaker.allow():
    events.add(MetricEvent(name: "flowbrigade.example.task.circuit_open", value: 1.0))
    return TaskOutcome(accepted: false, output: "dependency circuit is open", metrics: events)

  let acquired = bulkhead.acquire()
  if not acquired.allowed:
    events.add(MetricEvent(name: "flowbrigade.example.task.bulkhead_full", value: 1.0))
    return TaskOutcome(accepted: false, output: "too many concurrent tasks", metrics: events)

  try:
    let output = retry(
      policy = workerPolicy.retry.policy,
      maxAttempts = workerPolicy.retry.maxAttempts,
      sleep = proc(delay: Duration) =
        discard delay,
      operation = proc(): string =
        let childBudget = workflowBudget.clamp(30.sec)
        execute(task, childBudget)
    )
    breaker.recordSuccess()
    TaskOutcome(accepted: true, output: output, metrics: events)
  except CatchableError:
    breaker.recordFailure()
    events.add(MetricEvent(name: "flowbrigade.example.task.failed", value: 1.0))
    TaskOutcome(accepted: false, output: "task failed", metrics: events)
  finally:
    bulkhead.release()
```

The same code is available as a compile-checked recipe:
[batch_worker_runtime.nim](../recipes/batch_worker_runtime.nim).

## Scaling beyond one process

The example above uses in-process state. That is enough for local workers,
single-process tools, and unit tests.

Use storage-backed limiters when a limit must be shared across multiple worker
processes or machines:

```nim
let storage = redisStorage.asRateLimitStorage()
let limiter = initStoredFixedWindow(
  prefix = "workflow:task",
  limit = 1000,
  per = 1.min,
  storage = storage
)
```

External storage adapters own cross-process atomicity. FlowBrigade validates
keys, costs, and decisions around the adapter.

## Practical adoption order

1. Wrap one task type with `retry` and a `Deadline`.
2. Add `Bulkhead` if the worker can overload local CPU, memory, or file
   handles.
3. Add `CircuitBreaker` around external services or shared filesystems.
4. Add `BudgetLedger` if tenants, projects, or job classes have allowances.
5. Move repeated limits into `LimiterRegistry`.
6. Switch to `StoredFixedWindow` when multiple worker processes must share a
   limit.
7. Export `MetricEvent` values to your logging or metrics stack.

This keeps FlowBrigade as a small runtime-control layer while leaving workflow
language, scheduling, provenance, and resume semantics to the workflow system.
