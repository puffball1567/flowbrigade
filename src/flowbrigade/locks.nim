import std/[strutils, tables, times]

import ./internal/time_source

type
  FlowLockConfigError* = object of ValueError
  FlowLockError* = object of CatchableError

  LockAcquireResult* = object
    acquired*: bool
    key*: string
    token*: string
    ttl*: Duration

  LockLeaseStatus* = object
    held*: bool
    expired*: bool
    key*: string
    token*: string
    ttl*: Duration
    remaining*: Duration

  LockAcquireProc* = proc(key: string; ttl: Duration): LockAcquireResult {.closure.}
  LockReleaseProc* = proc(key: string): bool {.closure.}
  LockReleaseLeaseProc* = proc(lease: LockAcquireResult): bool {.closure.}
  LockRefreshProc* = proc(lease: LockAcquireResult; ttl: Duration): LockAcquireResult {.closure.}
  LockInspectProc* = proc(lease: LockAcquireResult): LockLeaseStatus {.closure.}

  LockStore* = object
    initialized: bool
    acquireProc: LockAcquireProc
    releaseProc: LockReleaseProc
    releaseLeaseProc: LockReleaseLeaseProc
    refreshProc: LockRefreshProc
    inspectProc: LockInspectProc

  LockState = object
    token: string
    expiresAt: Duration
    ttl: Duration

  InMemoryLockStore* = ref object
    locks: Table[string, LockState]
    timeSource: TimeSource
    nextToken: int

proc validateKey(key: string) =
  if key.len == 0:
    raise newException(FlowLockError, "lock key must not be empty")
  if key.strip().len == 0:
    raise newException(FlowLockError, "lock key must not be blank")
  for ch in key:
    if ord(ch) < 32 or ord(ch) == 127:
      raise newException(FlowLockError, "lock key must not contain control characters")

proc validateTtl(ttl: Duration) =
  if ttl <= initDuration():
    raise newException(FlowLockConfigError, "lock ttl must be positive")

proc initInMemoryLockStore*(timeSource: TimeSource): InMemoryLockStore =
  ## Creates an in-process lock store for tests and single-process tools.
  ##
  ## This store does not provide cross-process locking and does not add thread
  ## synchronization around shared mutation.
  InMemoryLockStore(locks: initTable[string, LockState](), timeSource: timeSource)

proc initInMemoryLockStore*(): InMemoryLockStore =
  initInMemoryLockStore(initTimeSource())

proc initLockStore*(
    acquire: LockAcquireProc;
    release: LockReleaseProc;
    releaseLease: LockReleaseLeaseProc = nil;
    refresh: LockRefreshProc = nil;
    inspectLease: LockInspectProc = nil
): LockStore =
  if acquire.isNil:
    raise newException(FlowLockConfigError, "lock acquire proc must not be nil")
  if release.isNil:
    raise newException(FlowLockConfigError, "lock release proc must not be nil")
  LockStore(
    initialized: true,
    acquireProc: acquire,
    releaseProc: release,
    releaseLeaseProc: releaseLease,
    refreshProc: refresh,
    inspectProc: inspectLease
  )

proc nextLockToken(store: InMemoryLockStore): string =
  inc store.nextToken
  $store.nextToken

proc acquire(store: InMemoryLockStore; key: string; ttl: Duration): LockAcquireResult =
  validateKey(key)
  validateTtl(ttl)
  let current = store.timeSource.now()
  let state = store.locks.getOrDefault(key)
  if state.expiresAt > current:
    return LockAcquireResult(acquired: false, key: key, ttl: ttl)
  let token = store.nextLockToken()
  store.locks[key] = LockState(token: token, expiresAt: current + ttl, ttl: ttl)
  LockAcquireResult(acquired: true, key: key, token: token, ttl: ttl)

proc release(store: InMemoryLockStore; key: string): bool =
  validateKey(key)
  result = store.locks.hasKey(key)
  store.locks.del(key)

proc release(store: InMemoryLockStore; lease: LockAcquireResult): bool =
  if not lease.acquired:
    return false
  validateKey(lease.key)
  let state = store.locks.getOrDefault(lease.key)
  if state.token.len == 0 or state.token != lease.token:
    return false
  store.locks.del(lease.key)
  true

proc refresh(store: InMemoryLockStore; lease: LockAcquireResult; ttl: Duration): LockAcquireResult =
  validateTtl(ttl)
  if not lease.acquired:
    return LockAcquireResult(acquired: false, key: lease.key, ttl: ttl)
  validateKey(lease.key)
  let current = store.timeSource.now()
  let state = store.locks.getOrDefault(lease.key)
  if state.token.len == 0:
    return LockAcquireResult(acquired: false, key: lease.key, token: lease.token, ttl: ttl)
  if state.token != lease.token:
    return LockAcquireResult(acquired: false, key: lease.key, token: lease.token, ttl: ttl)
  if state.expiresAt <= current:
    store.locks.del(lease.key)
    return LockAcquireResult(acquired: false, key: lease.key, token: lease.token, ttl: ttl)
  store.locks[lease.key] = LockState(token: lease.token, expiresAt: current + ttl, ttl: ttl)
  LockAcquireResult(acquired: true, key: lease.key, token: lease.token, ttl: ttl)

proc inspect(store: InMemoryLockStore; lease: LockAcquireResult): LockLeaseStatus =
  if not lease.acquired:
    return LockLeaseStatus(key: lease.key, token: lease.token, ttl: lease.ttl)
  validateKey(lease.key)
  let current = store.timeSource.now()
  let state = store.locks.getOrDefault(lease.key)
  result = LockLeaseStatus(key: lease.key, token: lease.token, ttl: lease.ttl)
  if state.token.len == 0:
    return
  if state.token != lease.token:
    return
  if state.expiresAt <= current:
    result.expired = true
    return
  result.held = true
  result.ttl = state.ttl
  result.remaining = state.expiresAt - current

proc asLockStore*(store: InMemoryLockStore): LockStore =
  if store.isNil:
    raise newException(FlowLockConfigError, "lock store must not be nil")
  initLockStore(
    acquire = proc(key: string; ttl: Duration): LockAcquireResult =
      store.acquire(key, ttl),
    release = proc(key: string): bool =
      store.release(key),
    releaseLease = proc(lease: LockAcquireResult): bool =
      store.release(lease),
    refresh = proc(lease: LockAcquireResult; ttl: Duration): LockAcquireResult =
      store.refresh(lease, ttl),
    inspectLease = proc(lease: LockAcquireResult): LockLeaseStatus =
      store.inspect(lease)
  )

proc validateStore(store: LockStore) =
  if not store.initialized:
    raise newException(FlowLockConfigError, "lock store is not initialized")
  if store.acquireProc.isNil:
    raise newException(FlowLockConfigError, "lock acquire proc must not be nil")
  if store.releaseProc.isNil:
    raise newException(FlowLockConfigError, "lock release proc must not be nil")

proc acquire*(store: LockStore; key: string; ttl: Duration): LockAcquireResult =
  store.validateStore()
  store.acquireProc(key, ttl)

proc release*(store: LockStore; key: string): bool =
  store.validateStore()
  store.releaseProc(key)

proc release*(store: LockStore; lease: LockAcquireResult): bool =
  store.validateStore()
  if not lease.acquired:
    return false
  if not store.releaseLeaseProc.isNil:
    return store.releaseLeaseProc(lease)
  store.releaseProc(lease.key)

proc refresh*(store: LockStore; lease: LockAcquireResult; ttl: Duration): LockAcquireResult =
  store.validateStore()
  if store.refreshProc.isNil:
    raise newException(FlowLockConfigError, "lock refresh proc must not be nil")
  store.refreshProc(lease, ttl)

proc inspect*(store: LockStore; lease: LockAcquireResult): LockLeaseStatus =
  store.validateStore()
  if store.inspectProc.isNil:
    raise newException(FlowLockConfigError, "lock inspect proc must not be nil")
  store.inspectProc(lease)

template withLock*(store: LockStore; key: string; ttl: Duration; body: untyped): untyped =
  let lease = store.acquire(key, ttl)
  if not lease.acquired:
    raise newException(FlowLockError, "lock is already held")
  try:
    body
  finally:
    discard store.release(lease)
