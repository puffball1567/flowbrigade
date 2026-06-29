import std/unittest

import flowbrigade

proc failOperation() =
  raise newException(ValueError, "failed")

suite "bulkhead":
  test "acquires permits up to capacity":
    var bulkhead = initBulkhead(capacity = 2)

    let first = bulkhead.acquire()
    let second = bulkhead.acquire()
    let third = bulkhead.acquire()

    check first.allowed
    check first.remaining == 1
    check second.allowed
    check second.remaining == 0
    check not third.allowed
    check third.inUse == 2
    check bulkhead.inUse() == 2
    check bulkhead.available() == 0

  test "releases permits":
    var bulkhead = initBulkhead(capacity = 1)

    check bulkhead.tryAcquire()
    bulkhead.release()

    check bulkhead.inUse() == 0
    check bulkhead.available() == 1
    check bulkhead.tryAcquire()

  test "rejects invalid capacity":
    expect BulkheadConfigError:
      discard initBulkhead(capacity = 0)

  test "rejects release without acquire":
    var bulkhead = initBulkhead(capacity = 1)

    expect BulkheadError:
      bulkhead.release()

  test "withBulkhead releases after success":
    var bulkhead = initBulkhead(capacity = 1)

    bulkhead.withBulkhead:
      check bulkhead.inUse() == 1

    check bulkhead.inUse() == 0

  test "withBulkhead releases after failure":
    var bulkhead = initBulkhead(capacity = 1)

    expect ValueError:
      bulkhead.withBulkhead:
        failOperation()

    check bulkhead.inUse() == 0

  test "withBulkhead raises when full":
    var bulkhead = initBulkhead(capacity = 1)

    check bulkhead.tryAcquire()

    expect BulkheadError:
      bulkhead.withBulkhead:
        discard
