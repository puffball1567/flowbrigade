import std/[times, unittest]

import flowbrigade
import flowbrigade/internal/time_source

proc failLockOperation() =
  raise newException(ValueError, "failed")

suite "flow locks":
  test "acquires and releases in-memory locks":
    let store = initInMemoryLockStore().asLockStore()

    let first = store.acquire("job:1", 1.min)
    let second = store.acquire("job:1", 1.min)

    check first.acquired
    check not second.acquired
    check store.release(first)
    check store.acquire("job:1", 1.min).acquired

  test "expires in-memory locks by ttl":
    let time = initManualTimeSource()
    let store = initInMemoryLockStore(time).asLockStore()

    check store.acquire("job:1", 1.min).acquired
    time.advance(59.sec)
    check not store.acquire("job:1", 1.min).acquired
    time.advance(1.sec)
    check store.acquire("job:1", 1.min).acquired

  test "rejects invalid lock input":
    let store = initInMemoryLockStore().asLockStore()

    expect FlowLockError:
      discard store.acquire("", 1.min)
    expect FlowLockError:
      discard store.acquire(" ", 1.min)
    expect FlowLockError:
      discard store.acquire("a" & char(10), 1.min)
    expect FlowLockConfigError:
      discard store.acquire("job:1", initDuration())

  test "refresh extends an active lease":
    let time = initManualTimeSource()
    let store = initInMemoryLockStore(time).asLockStore()

    let lease = store.acquire("job:1", 1.min)
    time.advance(45.sec)
    let refreshed = store.refresh(lease, 1.min)

    check refreshed.acquired
    check refreshed.key == lease.key
    check refreshed.token == lease.token
    check refreshed.ttl == 1.min

    time.advance(30.sec)
    check not store.acquire("job:1", 1.min).acquired
    time.advance(31.sec)
    check store.acquire("job:1", 1.min).acquired

  test "refresh rejects inactive leases and invalid ttl":
    let store = initInMemoryLockStore().asLockStore()
    let inactive = LockAcquireResult(acquired: false, key: "job:1", ttl: 1.min)
    let lease = store.acquire("job:1", 1.min)

    check not store.refresh(inactive, 1.min).acquired
    expect FlowLockConfigError:
      discard store.refresh(lease, initDuration())

  test "refresh after expiry fails and leaves the key acquirable":
    let time = initManualTimeSource()
    let store = initInMemoryLockStore(time).asLockStore()

    let lease = store.acquire("job:1", 1.min)
    time.advance(1.min)
    let refreshed = store.refresh(lease, 1.min)
    let next = store.acquire("job:1", 1.min)

    check not refreshed.acquired
    check next.acquired
    check next.token != lease.token

  test "refresh with a stale lease does not extend a newer lock":
    let time = initManualTimeSource()
    let store = initInMemoryLockStore(time).asLockStore()

    let first = store.acquire("job:1", 1.min)
    time.advance(1.min)
    let second = store.acquire("job:1", 1.min)
    let staleRefresh = store.refresh(first, 2.min)

    check first.acquired
    check second.acquired
    check not staleRefresh.acquired
    time.advance(59.sec)
    check not store.acquire("job:1", 1.min).acquired
    time.advance(1.sec)
    check store.acquire("job:1", 1.min).acquired

  test "inspect reports active lease state":
    let time = initManualTimeSource()
    let store = initInMemoryLockStore(time).asLockStore()

    let lease = store.acquire("job:1", 1.min)
    time.advance(15.sec)
    let status = store.inspect(lease)

    check status.held
    check not status.expired
    check status.key == lease.key
    check status.token == lease.token
    check status.ttl == lease.ttl
    check status.remaining == 45.sec

  test "inspect reports expired and stale leases":
    let time = initManualTimeSource()
    let store = initInMemoryLockStore(time).asLockStore()

    let expired = store.acquire("job:1", 1.min)
    time.advance(1.min)
    let expiredStatus = store.inspect(expired)
    let newer = store.acquire("job:1", 1.min)
    let staleStatus = store.inspect(expired)

    check not expiredStatus.held
    check expiredStatus.expired
    check expiredStatus.remaining == initDuration()
    check newer.acquired
    check not staleStatus.held
    check not staleStatus.expired
    check staleStatus.remaining == initDuration()

  test "rejects invalid lock stores":
    expect FlowLockConfigError:
      discard asLockStore(nil)

    let store = LockStore()

    expect FlowLockConfigError:
      discard store.acquire("job:1", 1.min)
    expect FlowLockConfigError:
      discard store.release("job:1")

  test "custom stores reject missing refresh and inspect capabilities":
    let store = initLockStore(
      acquire = proc(key: string; ttl: Duration): LockAcquireResult =
        LockAcquireResult(acquired: true, key: key, token: "1", ttl: ttl),
      release = proc(key: string): bool =
        true
    )
    let lease = store.acquire("job:1", 1.min)

    expect FlowLockConfigError:
      discard store.refresh(lease, 1.min)
    expect FlowLockConfigError:
      discard store.inspect(lease)

  test "lease release does not clear a newer lock":
    let time = initManualTimeSource()
    let store = initInMemoryLockStore(time).asLockStore()

    let first = store.acquire("job:1", 1.min)
    time.advance(1.min)
    let second = store.acquire("job:1", 1.min)

    check first.acquired
    check second.acquired
    check not store.release(first)
    check not store.acquire("job:1", 1.min).acquired
    check store.release(second)

  test "withLock releases after success":
    let store = initInMemoryLockStore().asLockStore()
    var ran = false

    store.withLock("job:1", 1.min):
      ran = true

    check ran
    check store.acquire("job:1", 1.min).acquired

  test "withLock releases after failure":
    let store = initInMemoryLockStore().asLockStore()

    expect ValueError:
      store.withLock("job:1", 1.min):
        failLockOperation()

    check store.acquire("job:1", 1.min).acquired

  test "withLock raises when already held":
    let store = initInMemoryLockStore().asLockStore()

    check store.acquire("job:1", 1.min).acquired

    expect FlowLockError:
      store.withLock("job:1", 1.min):
        discard
