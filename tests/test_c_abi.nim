import std/[times, unittest]

import flowbrigade_c

suite "C ABI":
  test "reports ABI version and last error":
    check fb_abi_version() == 1
    check fb_last_error() != nil

    var nanos: int64
    check fb_duration_parse("bad", 3, addr nanos) == FB_ERR_INVALID_ARGUMENT
    check ($fb_last_error()).len > 0

  test "parses and formats durations through stable buffers":
    var nanos: int64
    check fb_duration_parse("1s500ms", 7, addr nanos) == FB_OK
    check nanos == initDuration(milliseconds = 1500).inNanoseconds

    var needed: csize_t
    var buffer = newString(16)
    check fb_duration_format(nanos, cstring(buffer), csize_t(buffer.len), addr needed) == FB_OK
    check needed == 7.csize_t
    check $cstring(buffer) == "1s500ms"

    var tiny = newString(2)
    check fb_duration_format(nanos, cstring(tiny), csize_t(tiny.len), addr needed) ==
      FB_ERR_BUFFER_TOO_SMALL
    check needed == 7.csize_t

  test "token bucket handle can inspect and consume":
    var handle: pointer
    check fb_token_bucket_create(2, initDuration(seconds = 1).inNanoseconds, 3, addr handle) == FB_OK
    check not handle.isNil

    var result: FbRateLimitResult
    check fb_token_bucket_consume(handle, 2, addr result) == FB_OK
    check result.allowed == 1
    check result.limit == 3
    check result.remaining == 1

    check fb_token_bucket_consume(handle, 2, addr result) == FB_OK
    check result.allowed == 0
    check result.remaining == 1
    check result.retryAfterNs > 0

    fb_token_bucket_destroy(handle)

  test "backoff handles calculate delays":
    var handle: pointer
    var delayNs: int64

    check fb_fixed_backoff_create(initDuration(milliseconds = 250).inNanoseconds, FB_NO_JITTER, addr handle) == FB_OK
    check fb_backoff_delay_for(handle, 3, addr delayNs) == FB_OK
    check delayNs == initDuration(milliseconds = 250).inNanoseconds
    fb_backoff_destroy(handle)

    check fb_linear_backoff_create(
      initDuration(milliseconds = 100).inNanoseconds,
      initDuration(milliseconds = 50).inNanoseconds,
      initDuration(milliseconds = 250).inNanoseconds,
      FB_NO_JITTER,
      addr handle
    ) == FB_OK
    check fb_backoff_delay_for(handle, 3, addr delayNs) == FB_OK
    check delayNs == initDuration(milliseconds = 200).inNanoseconds
    fb_backoff_destroy(handle)

    check fb_exp_backoff_create(
      initDuration(milliseconds = 100).inNanoseconds,
      2.0,
      initDuration(seconds = 1).inNanoseconds,
      FB_NO_JITTER,
      addr handle
    ) == FB_OK
    check fb_backoff_delay_for(handle, 4, addr delayNs) == FB_OK
    check delayNs == initDuration(milliseconds = 800).inNanoseconds
    fb_backoff_destroy(handle)

  test "fixed window handle can inspect and consume":
    var handle: pointer
    check fb_fixed_window_create(2, initDuration(seconds = 60).inNanoseconds, addr handle) == FB_OK
    check not handle.isNil

    var result: FbRateLimitResult
    check fb_fixed_window_inspect(handle, 1, addr result) == FB_OK
    check result.allowed == 1
    check result.remaining == 1

    check fb_fixed_window_consume(handle, 1, addr result) == FB_OK
    check result.allowed == 1
    check result.remaining == 1
    check fb_fixed_window_consume(handle, 1, addr result) == FB_OK
    check result.allowed == 1
    check result.remaining == 0
    check fb_fixed_window_consume(handle, 1, addr result) == FB_OK
    check result.allowed == 0

    fb_fixed_window_destroy(handle)

  test "sliding window handle can inspect and consume":
    var handle: pointer
    check fb_sliding_window_create(2, initDuration(seconds = 60).inNanoseconds, addr handle) == FB_OK
    check not handle.isNil

    var result: FbRateLimitResult
    check fb_sliding_window_inspect(handle, 1, addr result) == FB_OK
    check result.allowed == 1
    check result.remaining == 1

    check fb_sliding_window_consume(handle, 1, addr result) == FB_OK
    check result.allowed == 1
    check result.remaining == 1
    check fb_sliding_window_consume(handle, 1, addr result) == FB_OK
    check result.allowed == 1
    check result.remaining == 0
    check fb_sliding_window_consume(handle, 1, addr result) == FB_OK
    check result.allowed == 0

    fb_sliding_window_destroy(handle)

  test "circuit breaker handle exposes state transitions":
    var handle: pointer
    check fb_circuit_breaker_create(2, initDuration(seconds = 10).inNanoseconds, addr handle) == FB_OK
    check not handle.isNil

    var allowed: int32
    var state: int32
    check fb_circuit_breaker_allow(handle, addr allowed) == FB_OK
    check allowed == 1
    check fb_circuit_breaker_record_failure(handle) == FB_OK
    check fb_circuit_breaker_state(handle, addr state) == FB_OK
    check state == FB_CIRCUIT_CLOSED

    check fb_circuit_breaker_record_failure(handle) == FB_OK
    check fb_circuit_breaker_state(handle, addr state) == FB_OK
    check state == FB_CIRCUIT_OPEN
    check fb_circuit_breaker_allow(handle, addr allowed) == FB_OK
    check allowed == 0

    fb_circuit_breaker_destroy(handle)

  test "bulkhead handle tracks permits":
    var handle: pointer
    check fb_bulkhead_create(2, addr handle) == FB_OK
    check not handle.isNil

    var result: FbBulkheadResult
    check fb_bulkhead_inspect(handle, addr result) == FB_OK
    check result.allowed == 1
    check result.capacity == 2
    check result.inUse == 0
    check result.remaining == 2

    check fb_bulkhead_acquire(handle, addr result) == FB_OK
    check result.allowed == 1
    check result.inUse == 1
    check result.remaining == 1
    check fb_bulkhead_acquire(handle, addr result) == FB_OK
    check result.allowed == 1
    check result.inUse == 2
    check result.remaining == 0
    check fb_bulkhead_acquire(handle, addr result) == FB_OK
    check result.allowed == 0
    check result.inUse == 2

    check fb_bulkhead_release(handle) == FB_OK
    check fb_bulkhead_inspect(handle, addr result) == FB_OK
    check result.inUse == 1
    check result.remaining == 1

    fb_bulkhead_destroy(handle)

  test "timeout and deadline handles expose elapsed state":
    var timeoutHandle: pointer
    check fb_timeout_create(initDuration(seconds = 1).inNanoseconds, addr timeoutHandle) == FB_OK
    check not timeoutHandle.isNil

    var flag: int32
    var elapsedNs: int64
    var remainingNs: int64
    check fb_timeout_expired(timeoutHandle, addr flag) == FB_OK
    check flag == 0
    check fb_timeout_elapsed(timeoutHandle, addr elapsedNs) == FB_OK
    check elapsedNs >= 0
    check fb_timeout_remaining(timeoutHandle, addr remainingNs) == FB_OK
    check remainingNs > 0
    check remainingNs <= initDuration(seconds = 1).inNanoseconds
    fb_timeout_destroy(timeoutHandle)

    var zeroTimeout: pointer
    check fb_timeout_create(0, addr zeroTimeout) == FB_OK
    check fb_timeout_expired(zeroTimeout, addr flag) == FB_OK
    check flag == 1
    fb_timeout_destroy(zeroTimeout)

    var deadlineHandle: pointer
    check fb_deadline_create(initDuration(seconds = 1).inNanoseconds, addr deadlineHandle) == FB_OK
    check not deadlineHandle.isNil
    check fb_deadline_expired(deadlineHandle, addr flag) == FB_OK
    check flag == 0
    check fb_deadline_remaining(deadlineHandle, addr remainingNs) == FB_OK
    check remainingNs > 0

    var clampedNs: int64
    check fb_deadline_clamp(deadlineHandle, initDuration(seconds = 10).inNanoseconds, addr clampedNs) == FB_OK
    check clampedNs <= initDuration(seconds = 1).inNanoseconds
    check clampedNs > 0
    fb_deadline_destroy(deadlineHandle)

  test "budget ledger handle tracks keyed usage":
    var handle: pointer
    check fb_budget_ledger_create(10, initDuration(minutes = 1).inNanoseconds, addr handle) == FB_OK
    check not handle.isNil

    var result: FbBudgetResult
    check fb_budget_inspect(handle, " tenant-a ", 10, 4, addr result) == FB_OK
    check result.allowed == 1
    check result.limit == 10
    check result.used == 4
    check result.remaining == 6

    check fb_budget_consume(handle, " tenant-a ", 10, 7, addr result) == FB_OK
    check result.allowed == 1
    check result.used == 7
    check result.remaining == 3

    check fb_budget_consume(handle, "tenant-a", 8, 4, addr result) == FB_OK
    check result.allowed == 0
    check result.used == 7
    check result.remaining == 3
    check result.retryAfterNs > 0

    check fb_budget_refund(handle, "tenant-a", 8, 3, addr result) == FB_OK
    check result.allowed == 1
    check result.used == 4
    check result.remaining == 6

    check fb_budget_reset(handle, "tenant-a", 8, addr result) == FB_OK
    check result.allowed == 1
    check result.used == 0
    check result.remaining == 10

    check fb_budget_consume(handle, "tenant-b", 8, 10, addr result) == FB_OK
    check result.allowed == 1
    check fb_budget_reset_all(handle) == FB_OK
    check fb_budget_inspect(handle, "tenant-b", 8, 1, addr result) == FB_OK
    check result.remaining == 9

    fb_budget_ledger_destroy(handle)

  test "lock store handle manages opaque leases":
    var store: pointer
    check fb_lock_store_create(addr store) == FB_OK
    check not store.isNil

    var firstLease: pointer
    var secondLease: pointer
    var result: FbLockAcquireResult
    check fb_lock_acquire(store, "job:1", 5, initDuration(minutes = 1).inNanoseconds, addr firstLease, addr result) == FB_OK
    check not firstLease.isNil
    check result.acquired == 1
    check result.ttlNs == initDuration(minutes = 1).inNanoseconds

    check fb_lock_acquire(store, "job:1", 5, initDuration(minutes = 1).inNanoseconds, addr secondLease, addr result) == FB_OK
    check not secondLease.isNil
    check result.acquired == 0

    var status: FbLockStatus
    check fb_lock_inspect(store, firstLease, addr status) == FB_OK
    check status.held == 1
    check status.expired == 0
    check status.remainingNs > 0

    check fb_lock_refresh(store, firstLease, initDuration(minutes = 2).inNanoseconds, addr result) == FB_OK
    check result.acquired == 1
    check result.ttlNs == initDuration(minutes = 2).inNanoseconds

    var released: int32
    check fb_lock_release(store, secondLease, addr released) == FB_OK
    check released == 0
    check fb_lock_release(store, firstLease, addr released) == FB_OK
    check released == 1

    var thirdLease: pointer
    check fb_lock_acquire(store, "job:1", 5, initDuration(minutes = 1).inNanoseconds, addr thirdLease, addr result) == FB_OK
    check result.acquired == 1
    check fb_lock_release_key(store, "job:1", 5, addr released) == FB_OK
    check released == 1

    fb_lock_lease_destroy(firstLease)
    fb_lock_lease_destroy(secondLease)
    fb_lock_lease_destroy(thirdLease)
    fb_lock_store_destroy(store)

  test "C ABI rejects invalid arguments as error codes":
    var result: FbRateLimitResult
    var budgetResult: FbBudgetResult
    var lockResult: FbLockAcquireResult
    check fb_token_bucket_consume(nil, 1, addr result) == FB_ERR_INVALID_ARGUMENT
    check ($fb_last_error()).len > 0
    check fb_fixed_window_create(0, initDuration(seconds = 1).inNanoseconds, nil) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_duration_parse(nil, 0, nil) == FB_ERR_INVALID_ARGUMENT
    check fb_backoff_delay_for(nil, 1, nil) == FB_ERR_INVALID_ARGUMENT
    check fb_bulkhead_create(0, nil) == FB_ERR_INVALID_ARGUMENT
    check fb_timeout_create(-1, nil) == FB_ERR_INVALID_ARGUMENT
    check fb_deadline_clamp(nil, 1, nil) == FB_ERR_INVALID_ARGUMENT
    check fb_budget_ledger_create(0, initDuration(minutes = 1).inNanoseconds, nil) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_budget_consume(nil, "tenant", 6, 1, addr budgetResult) == FB_ERR_INVALID_ARGUMENT

    var budgetHandle: pointer
    check fb_budget_ledger_create(10, initDuration(minutes = 1).inNanoseconds, addr budgetHandle) == FB_OK
    check fb_budget_consume(budgetHandle, nil, 0, 1, addr budgetResult) == FB_ERR_INVALID_ARGUMENT
    check fb_budget_consume(budgetHandle, " ", 1, 1, addr budgetResult) == FB_ERR_INVALID_ARGUMENT
    check fb_budget_consume(budgetHandle, "tenant", 6, 0, addr budgetResult) == FB_ERR_INVALID_ARGUMENT
    check fb_budget_consume(budgetHandle, "tenant", 6, 1, nil) == FB_ERR_INVALID_ARGUMENT
    fb_budget_ledger_destroy(budgetHandle)

    check fb_lock_store_create(nil) == FB_ERR_INVALID_ARGUMENT
    check fb_lock_acquire(nil, "job", 3, initDuration(minutes = 1).inNanoseconds, nil, addr lockResult) ==
      FB_ERR_INVALID_ARGUMENT
    var lockStore: pointer
    check fb_lock_store_create(addr lockStore) == FB_OK
    var lockLease: pointer
    check fb_lock_acquire(lockStore, nil, 0, initDuration(minutes = 1).inNanoseconds, addr lockLease, addr lockResult) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_lock_acquire(lockStore, " ", 1, initDuration(minutes = 1).inNanoseconds, addr lockLease, addr lockResult) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_lock_acquire(lockStore, "job", 3, 0, addr lockLease, addr lockResult) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_lock_release(lockStore, nil, nil) == FB_ERR_INVALID_ARGUMENT
    check fb_lock_refresh(lockStore, nil, initDuration(minutes = 1).inNanoseconds, addr lockResult) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_lock_inspect(lockStore, nil, nil) == FB_ERR_INVALID_ARGUMENT
    fb_lock_store_destroy(lockStore)
