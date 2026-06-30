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

  test "keyed bulkhead limits each key independently":
    var bulkhead = initKeyedBulkhead[string](capacity = 2, maxKeys = 4)

    let first = bulkhead.acquire("tenant:a")
    let second = bulkhead.acquire("tenant:a")
    let third = bulkhead.acquire("tenant:a")
    let other = bulkhead.acquire("tenant:b")

    check first.allowed
    check first.inUse == 1
    check second.allowed
    check second.remaining == 0
    check not third.allowed
    check third.inUse == 2
    check other.allowed
    check bulkhead.inspect("tenant:a").remaining == 0
    check bulkhead.inspect("tenant:b").remaining == 1
    check bulkhead.activeKeys() == 2

  test "keyed bulkhead releases and clears keys":
    var bulkhead = initKeyedBulkhead[string](capacity = 2)

    check bulkhead.tryAcquire("tenant:a")
    check bulkhead.tryAcquire("tenant:a")
    bulkhead.release("tenant:a")

    check bulkhead.inspect("tenant:a").inUse == 1
    check bulkhead.clear("tenant:a")
    check bulkhead.inspect("tenant:a").inUse == 0
    check not bulkhead.clear("tenant:a")
    check bulkhead.activeKeys() == 0

  test "keyed bulkhead supports non-string keys":
    var bulkhead = initKeyedBulkhead[int](capacity = 1, maxKeys = 2)

    check bulkhead.tryAcquire(10)
    check not bulkhead.tryAcquire(10)
    check bulkhead.tryAcquire(20)
    check bulkhead.inspect(10).inUse == 1
    check bulkhead.inspect(20).inUse == 1
    check bulkhead.activeKeys() == 2

  test "keyed bulkhead scoped helper releases after success and failure":
    var bulkhead = initKeyedBulkhead[string](capacity = 1)

    bulkhead.withBulkhead("tenant:a"):
      check bulkhead.inspect("tenant:a").inUse == 1
    check bulkhead.inspect("tenant:a").inUse == 0

    expect ValueError:
      bulkhead.withBulkhead("tenant:a"):
        failOperation()
    check bulkhead.inspect("tenant:a").inUse == 0

  test "keyed bulkhead rejects invalid keys and capacity overflow":
    var bulkhead = initKeyedBulkhead[string](capacity = 1, maxKeys = 1)

    expect BulkheadConfigError:
      discard initKeyedBulkhead[string](capacity = 0)
    expect BulkheadConfigError:
      discard initKeyedBulkhead[string](capacity = 1, maxKeys = 0)
    expect BulkheadError:
      discard bulkhead.acquire(" ")
    expect BulkheadError:
      discard bulkhead.acquire("tenant:" & chr(10))

    check bulkhead.tryAcquire("tenant:a")
    expect BulkheadError:
      discard bulkhead.acquire("tenant:b")
    expect BulkheadError:
      bulkhead.release("tenant:b")
    check bulkhead.activeKeys() == 1
