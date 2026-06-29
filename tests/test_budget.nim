import std/[times, unittest]

import flowbrigade
import flowbrigade/internal/time_source

suite "budget ledger":
  test "consumes quota per key":
    var ledger = initBudgetLedger(limit = 10, per = 1.hr)

    let first = ledger.consume("tenant-a", 4)
    let second = ledger.consume("tenant-a", 6)
    let denied = ledger.consume("tenant-a", 1)

    check first.allowed
    check first.used == 4
    check first.remaining == 6
    check second.allowed
    check second.used == 10
    check second.remaining == 0
    check not denied.allowed
    check denied.used == 10
    check denied.remaining == 0

  test "keeps keys isolated":
    var ledger = initBudgetLedger(limit = 2, per = 1.hr)

    check ledger.allow("tenant-a", 2)
    check not ledger.allow("tenant-a", 1)
    check ledger.allow("tenant-b", 1)

  test "inspect does not consume":
    var ledger = initBudgetLedger(limit = 5, per = 1.hr)

    let inspected = ledger.inspect("tenant-a", 3)
    let consumed = ledger.consume("tenant-a", 5)

    check inspected.allowed
    check inspected.used == 3
    check inspected.remaining == 2
    check consumed.allowed
    check consumed.used == 5
    check consumed.remaining == 0

  test "trims keys before use":
    var ledger = initBudgetLedger(limit = 2, per = 1.hr)

    check ledger.allow(" tenant-a ", 2)
    check not ledger.allow("tenant-a", 1)

  test "rejects empty keys and non-positive costs":
    var ledger = initBudgetLedger(limit = 2, per = 1.hr)

    expect BudgetError:
      discard ledger.consume("   ")
    expect BudgetError:
      discard ledger.consume("tenant-a", 0)
    expect BudgetError:
      discard ledger.consume("tenant-a", -1)

  test "denies a cost larger than the period budget without mutating usage":
    var ledger = initBudgetLedger(limit = 5, per = 1.hr)

    let denied = ledger.consume("tenant-a", 6)
    let allowed = ledger.consume("tenant-a", 5)

    check not denied.allowed
    check denied.used == 0
    check denied.remaining == 5
    check allowed.allowed

  test "resets after the configured period":
    let time = initManualTimeSource()
    var ledger = initBudgetLedger(limit = 3, per = 1.hr, timeSource = time)

    check ledger.allow("tenant-a", 3)
    check not ledger.allow("tenant-a", 1)

    time.advance(59.min)
    check not ledger.allow("tenant-a", 1)

    time.advance(1.min)
    let afterReset = ledger.consume("tenant-a", 1)
    check afterReset.allowed
    check afterReset.used == 1
    check afterReset.remaining == 2

  test "refund clamps usage at zero":
    var ledger = initBudgetLedger(limit = 10, per = 1.hr)

    discard ledger.consume("tenant-a", 6)
    let partial = ledger.refund("tenant-a", 4)
    let over = ledger.refund("tenant-a", 10)

    check partial.used == 2
    check partial.remaining == 8
    check over.used == 0
    check over.remaining == 10

  test "reset clears one key and resetAll clears every key":
    var ledger = initBudgetLedger(limit = 2, per = 1.hr)

    discard ledger.consume("tenant-a", 2)
    discard ledger.consume("tenant-b", 2)

    let resetA = ledger.reset("tenant-a")
    check resetA.used == 0
    check ledger.allow("tenant-a", 2)
    check not ledger.allow("tenant-b", 1)

    ledger.resetAll()
    check ledger.allow("tenant-b", 2)

  test "config and presets build usable ledgers":
    var daily = initBudgetLedger(dailyQuotaConfig(3))
    var monthly = initBudgetLedger(monthlyQuotaConfig(4))

    check daily.limit == 3
    check daily.period == 1.day
    check monthly.limit == 4
    check monthly.period == 30.day

  test "configuration rejects invalid values":
    expect BudgetConfigError:
      discard initBudgetLedger(limit = 0, per = 1.hr)
    expect BudgetConfigError:
      discard initBudgetLedger(limit = 1, per = initDuration())

  test "converts budget decisions and events to metric events":
    let decision = deniedBudgetResult(
      key = "tenant-a",
      limit = 10,
      used = 10,
      cost = 1,
      retryAfter = 1.hr,
      resetAfter = 1.hr
    )
    let metric = metricEvent(decision)

    check metric.name == "flowbrigade.budget.decision"
    check ("key", "tenant-a") in metric.tags
    check ("allowed", "false") in metric.tags
    check ("remaining", "0") in metric.tags

    let eventMetric = metricEvent(BudgetEvent(
      kind: budgetConsume,
      key: "tenant-a",
      amount: 1,
      result: decision
    ))

    check eventMetric.name == "flowbrigade.budget.consume"
    check ("amount", "1") in eventMetric.tags
