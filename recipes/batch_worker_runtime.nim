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

let workflowDeadline = initDeadline(after = 2.min)
let first = runTask(
  WorkflowTask(id: "align-001", tenant: "lab-a", cost: 250, payload: "reads"),
  workflowDeadline
)

doAssert first.accepted
doAssert first.output == "processed:align-001:READS"
doAssert first.metrics.toPrometheusText().contains("flowbrigade_budget_decision")
doAssert first.metrics.toJsonLines().contains("flowbrigade.ratelimit.decision")
