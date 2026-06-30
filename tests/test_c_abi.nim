import std/[strutils, times, unittest]

import flowbrigade_c

type RetryState = object
  calls: int32
  succeedAt: int32
  sleepCalls: int32
  failSleep: int32
  lastDelayNs: int64

type FallbackState = object
  calls: array[4, int32]
  statuses: array[4, int32]
  predicateCalls: int32
  stopStatus: int32

type StorageState = object
  used: int32
  failStatus: int32
  clearCalls: int32
  lastKey: string

proc retryOperation(userData: pointer; attempt: int32): cint {.cdecl.} =
  let state = cast[ptr RetryState](userData)
  state.calls = attempt
  if attempt >= state.succeedAt:
    FB_OK
  else:
    77.cint

proc retryNeverOperation(userData: pointer; attempt: int32): cint {.cdecl.} =
  let state = cast[ptr RetryState](userData)
  state.calls = attempt
  88.cint

proc retrySleep(userData: pointer; delayNs: int64; attempt: int32): cint {.cdecl.} =
  let state = cast[ptr RetryState](userData)
  inc state.sleepCalls
  state.lastDelayNs = delayNs
  if state.failSleep == 1:
    return 66.cint
  FB_OK

proc fallbackOperation(userData: pointer; providerIndex: int32): cint {.cdecl.} =
  let state = cast[ptr FallbackState](userData)
  inc state.calls[providerIndex]
  state.statuses[providerIndex]

proc fallbackPredicate(userData: pointer; status: int32; providerIndex: int32): cint {.cdecl.} =
  let state = cast[ptr FallbackState](userData)
  discard providerIndex
  inc state.predicateCalls
  if state.stopStatus != 0 and status == state.stopStatus:
    return 0.cint
  1.cint

proc storageInspect(
    userData: pointer;
    key: cstring;
    keyLen: csize_t;
    limit: int32;
    perNs: int64;
    cost: int32;
    currentNs: int64;
    outResult: ptr FbRateLimitResult
): cint {.cdecl.} =
  let state = cast[ptr StorageState](userData)
  if state.failStatus != 0:
    return state.failStatus.cint
  if outResult.isNil:
    return FB_ERR_INVALID_ARGUMENT
  discard perNs
  discard currentNs
  state.lastKey = newString(int(keyLen))
  if keyLen > 0:
    copyMem(addr state.lastKey[0], key, int(keyLen))
  let remaining = limit - state.used
  outResult[] = FbRateLimitResult(
    allowed: (if state.used + cost <= limit: 1'i32 else: 0'i32),
    limit: limit,
    remaining: max(0'i32, remaining - (if state.used + cost <= limit: cost else: 0'i32)),
    retryAfterNs: (if state.used + cost <= limit: 0'i64 else: perNs),
    resetAfterNs: perNs
  )
  FB_OK

proc storageConsume(
    userData: pointer;
    key: cstring;
    keyLen: csize_t;
    limit: int32;
    perNs: int64;
    cost: int32;
    currentNs: int64;
    outResult: ptr FbRateLimitResult
): cint {.cdecl.} =
  let state = cast[ptr StorageState](userData)
  let status = storageInspect(userData, key, keyLen, limit, perNs, cost, currentNs, outResult)
  if status != FB_OK:
    return status
  if outResult[].allowed != 0:
    state.used += cost
  FB_OK

proc storageClear(userData: pointer; key: cstring; keyLen: csize_t; outCleared: ptr int32): cint {.cdecl.} =
  let state = cast[ptr StorageState](userData)
  if state.failStatus != 0:
    return state.failStatus.cint
  if outCleared.isNil:
    return FB_ERR_INVALID_ARGUMENT
  state.lastKey = newString(int(keyLen))
  if keyLen > 0:
    copyMem(addr state.lastKey[0], key, int(keyLen))
  inc state.clearCalls
  outCleared[] = (if state.used > 0: 1'i32 else: 0'i32)
  state.used = 0
  FB_OK

suite "C ABI":
  test "reports ABI version and last error":
    check fb_abi_version() == 1
    check $fb_abi_version_string() == "1"
    check fb_last_error() != nil

    var supported: int32
    check fb_abi_supports("storage-callback", 16, addr supported) == FB_OK
    check supported == 1
    check fb_abi_supports("unknown", 7, addr supported) == FB_OK
    check supported == 0
    check fb_abi_supports(nil, 0, addr supported) == FB_ERR_INVALID_ARGUMENT
    check fb_abi_supports("metrics", 7, nil) == FB_ERR_INVALID_ARGUMENT

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

  test "converts result structs to observability text":
    var rateDecision = FbRateLimitResult(
      allowed: 0,
      limit: 10,
      remaining: 2,
      retryAfterNs: initDuration(seconds = 30).inNanoseconds,
      resetAfterNs: initDuration(minutes = 1).inNanoseconds
    )
    var needed: csize_t
    var buffer = newString(256)
    check fb_rate_limit_result_to_json(addr rateDecision, cstring(buffer), csize_t(buffer.len), addr needed) == FB_OK
    let jsonLine = $cstring(buffer)
    check "\"name\":\"flowbrigade.ratelimit.decision\"" in jsonLine
    check "\"allowed\":\"false\"" in jsonLine

    check fb_rate_limit_result_to_prometheus(addr rateDecision, cstring(buffer), csize_t(buffer.len), addr needed) == FB_OK
    let prometheus = $cstring(buffer)
    check prometheus.startsWith("flowbrigade_ratelimit_decision")
    check "allowed=\"false\"" in prometheus

    var budgetDecision = FbBudgetResult(
      allowed: 1,
      limit: 100,
      used: 25,
      remaining: 75,
      cost: 25,
      retryAfterNs: 0,
      resetAfterNs: initDuration(minutes = 1).inNanoseconds
    )
    check fb_budget_result_to_json(addr budgetDecision, "tenant-a", 8, cstring(buffer), csize_t(buffer.len), addr needed) == FB_OK
    check "\"name\":\"flowbrigade.budget.decision\"" in $cstring(buffer)
    check "\"key\":\"tenant-a\"" in $cstring(buffer)

    var tiny = newString(4)
    check fb_budget_result_to_prometheus(addr budgetDecision, "tenant-a", 8, cstring(tiny), csize_t(tiny.len), addr needed) ==
      FB_ERR_BUFFER_TOO_SMALL
    check needed > 4.csize_t
    check fb_rate_limit_result_to_json(nil, cstring(buffer), csize_t(buffer.len), addr needed) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_budget_result_to_json(addr budgetDecision, nil, 1, cstring(buffer), csize_t(buffer.len), addr needed) ==
      FB_ERR_INVALID_ARGUMENT

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

  test "throttle and debouncer handles expose traffic shaping state":
    var throttleHandle: pointer
    check fb_throttle_create(initDuration(seconds = 1).inNanoseconds, addr throttleHandle) == FB_OK
    check not throttleHandle.isNil

    var flag: int32
    check fb_throttle_allow(throttleHandle, addr flag) == FB_OK
    check flag == 1
    check fb_throttle_allow(throttleHandle, addr flag) == FB_OK
    check flag == 0
    check fb_throttle_reset(throttleHandle) == FB_OK
    check fb_throttle_allow(throttleHandle, addr flag) == FB_OK
    check flag == 1
    fb_throttle_destroy(throttleHandle)

    var debouncerHandle: pointer
    check fb_debouncer_create(initDuration(seconds = 1).inNanoseconds, addr debouncerHandle) == FB_OK
    check not debouncerHandle.isNil
    check fb_debouncer_ready(debouncerHandle, addr flag) == FB_OK
    check flag == 0
    check fb_debouncer_call(debouncerHandle) == FB_OK
    check fb_debouncer_ready(debouncerHandle, addr flag) == FB_OK
    check flag == 0
    check fb_debouncer_cancel(debouncerHandle) == FB_OK
    check fb_debouncer_consume_ready(debouncerHandle, addr flag) == FB_OK
    check flag == 0
    fb_debouncer_destroy(debouncerHandle)

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

    check fb_throttle_create(0, nil) == FB_ERR_INVALID_ARGUMENT
    var throttleHandle: pointer
    check fb_throttle_create(initDuration(seconds = 1).inNanoseconds, addr throttleHandle) == FB_OK
    check fb_throttle_allow(nil, nil) == FB_ERR_INVALID_ARGUMENT
    check fb_throttle_allow(throttleHandle, nil) == FB_ERR_INVALID_ARGUMENT
    check fb_throttle_reset(nil) == FB_ERR_INVALID_ARGUMENT
    fb_throttle_destroy(throttleHandle)

    check fb_debouncer_create(0, nil) == FB_ERR_INVALID_ARGUMENT
    var debouncerHandle: pointer
    check fb_debouncer_create(initDuration(seconds = 1).inNanoseconds, addr debouncerHandle) == FB_OK
    check fb_debouncer_call(nil) == FB_ERR_INVALID_ARGUMENT
    check fb_debouncer_ready(nil, nil) == FB_ERR_INVALID_ARGUMENT
    check fb_debouncer_ready(debouncerHandle, nil) == FB_ERR_INVALID_ARGUMENT
    check fb_debouncer_consume_ready(nil, nil) == FB_ERR_INVALID_ARGUMENT
    check fb_debouncer_cancel(nil) == FB_ERR_INVALID_ARGUMENT
    fb_debouncer_destroy(debouncerHandle)

  test "retry callback ABI retries operation callbacks":
    var policy: pointer
    check fb_fixed_backoff_create(initDuration(milliseconds = 25).inNanoseconds, FB_NO_JITTER, addr policy) == FB_OK

    var state = RetryState(succeedAt: 3)
    var result: FbRetryResult
    check fb_retry_run(policy, 5, retryOperation, retrySleep, addr state, addr result) == FB_OK
    check result.succeeded == 1
    check result.attempts == 3
    check result.lastStatus == FB_OK
    check state.calls == 3
    check state.sleepCalls == 2
    check state.lastDelayNs == initDuration(milliseconds = 25).inNanoseconds

    var failedState = RetryState()
    check fb_retry_run(policy, 2, retryNeverOperation, retrySleep, addr failedState, addr result) == FB_OK
    check result.succeeded == 0
    check result.attempts == 2
    check result.lastStatus == 88
    check failedState.sleepCalls == 1

    var sleepFailureState = RetryState(succeedAt: 3, failSleep: 1)
    check fb_retry_run(policy, 3, retryOperation, retrySleep, addr sleepFailureState, addr result) ==
      FB_ERR_INVALID_ARGUMENT
    check result.succeeded == 0
    check result.attempts == 1
    check result.lastStatus == 66

    fb_backoff_destroy(policy)

  test "retry callback ABI rejects invalid arguments":
    var result: FbRetryResult
    var policy: pointer
    check fb_fixed_backoff_create(initDuration(milliseconds = 25).inNanoseconds, FB_NO_JITTER, addr policy) == FB_OK
    check fb_retry_run(nil, 3, retryOperation, nil, nil, addr result) == FB_ERR_INVALID_ARGUMENT
    check fb_retry_run(policy, 0, retryOperation, nil, nil, addr result) == FB_ERR_INVALID_ARGUMENT
    check fb_retry_run(policy, 3, nil, nil, nil, addr result) == FB_ERR_INVALID_ARGUMENT
    check fb_retry_run(policy, 3, retryOperation, nil, nil, nil) == FB_ERR_INVALID_ARGUMENT
    fb_backoff_destroy(policy)

  test "fallback callback ABI tries providers in order":
    var state = FallbackState()
    state.statuses[0] = 7
    state.statuses[1] = FB_OK
    var providers = [
      FbFallbackProvider(operation: fallbackOperation, userData: addr state, breaker: nil),
      FbFallbackProvider(operation: fallbackOperation, userData: addr state, breaker: nil)
    ]
    var result: FbFallbackResult

    check fb_fallback_run(cast[ptr UncheckedArray[FbFallbackProvider]](addr providers[0]), csize_t(providers.len), nil, addr result) == FB_OK
    check result.succeeded == 1
    check result.attempts == 2
    check result.providerIndex == 1
    check result.failedCount == 1
    check result.lastStatus == FB_OK
    check state.calls[0] == 1
    check state.calls[1] == 1

  test "fallback callback ABI reports exhausted providers and predicate stops":
    var state = FallbackState()
    state.statuses[0] = 7
    state.statuses[1] = 8
    var providers = [
      FbFallbackProvider(operation: fallbackOperation, userData: addr state, breaker: nil),
      FbFallbackProvider(operation: fallbackOperation, userData: addr state, breaker: nil)
    ]
    var result: FbFallbackResult
    check fb_fallback_run(cast[ptr UncheckedArray[FbFallbackProvider]](addr providers[0]), csize_t(providers.len), nil, addr result) == FB_OK
    check result.succeeded == 0
    check result.attempts == 2
    check result.providerIndex == -1
    check result.failedCount == 2
    check result.lastStatus == 8

    var stoppedState = FallbackState(stopStatus: 7)
    stoppedState.statuses[0] = 7
    stoppedState.statuses[1] = FB_OK
    var stoppedProviders = [
      FbFallbackProvider(operation: fallbackOperation, userData: addr stoppedState, breaker: nil),
      FbFallbackProvider(operation: fallbackOperation, userData: addr stoppedState, breaker: nil)
    ]
    check fb_fallback_run(
      cast[ptr UncheckedArray[FbFallbackProvider]](addr stoppedProviders[0]),
      csize_t(stoppedProviders.len),
      fallbackPredicate,
      addr result
    ) == FB_OK
    check result.succeeded == 0
    check result.providerIndex == 0
    check result.failedCount == 1
    check stoppedState.calls[1] == 0
    check stoppedState.predicateCalls == 1

  test "fallback callback ABI can skip and record circuit breaker providers":
    var breaker: pointer
    check fb_circuit_breaker_create(1, initDuration(minutes = 1).inNanoseconds, addr breaker) == FB_OK
    check fb_circuit_breaker_record_failure(breaker) == FB_OK

    var state = FallbackState()
    state.statuses[0] = FB_OK
    state.statuses[1] = FB_OK
    var providers = [
      FbFallbackProvider(operation: fallbackOperation, userData: addr state, breaker: breaker),
      FbFallbackProvider(operation: fallbackOperation, userData: addr state, breaker: nil)
    ]
    var result: FbFallbackResult
    check fb_fallback_run(cast[ptr UncheckedArray[FbFallbackProvider]](addr providers[0]), csize_t(providers.len), nil, addr result) == FB_OK
    check result.succeeded == 1
    check result.providerIndex == 1
    check result.failedCount == 1
    check state.calls[0] == 0
    check state.calls[1] == 1
    fb_circuit_breaker_destroy(breaker)

    check fb_circuit_breaker_create(1, initDuration(minutes = 1).inNanoseconds, addr breaker) == FB_OK
    var failingState = FallbackState()
    failingState.statuses[0] = 9
    var failingProviders = [
      FbFallbackProvider(operation: fallbackOperation, userData: addr failingState, breaker: breaker)
    ]
    check fb_fallback_run(cast[ptr UncheckedArray[FbFallbackProvider]](addr failingProviders[0]), csize_t(failingProviders.len), nil, addr result) == FB_OK
    var circuitState: int32
    check fb_circuit_breaker_state(breaker, addr circuitState) == FB_OK
    check circuitState == FB_CIRCUIT_OPEN
    fb_circuit_breaker_destroy(breaker)

  test "fallback callback ABI rejects invalid arguments":
    var result: FbFallbackResult
    check fb_fallback_run(nil, 1, nil, addr result) == FB_ERR_INVALID_ARGUMENT
    var state = FallbackState()
    var invalidProviders = [
      FbFallbackProvider(operation: nil, userData: addr state, breaker: nil)
    ]
    check fb_fallback_run(cast[ptr UncheckedArray[FbFallbackProvider]](addr invalidProviders[0]), 0, nil, addr result) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_fallback_run(cast[ptr UncheckedArray[FbFallbackProvider]](addr invalidProviders[0]), 1, nil, addr result) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_fallback_run(cast[ptr UncheckedArray[FbFallbackProvider]](addr invalidProviders[0]), 1, nil, nil) ==
      FB_ERR_INVALID_ARGUMENT

  test "limiter registry C ABI registers and uses named limiters":
    var registry: pointer
    check fb_limiter_registry_create(addr registry) == FB_OK
    check not registry.isNil

    var result: FbRateLimitResult
    check fb_limiter_registry_add_fixed_window(
      registry,
      "global",
      6,
      1,
      initDuration(minutes = 1).inNanoseconds
    ) == FB_OK
    check fb_limiter_registry_consume(registry, "global", 6, "global", 6, 1, addr result) == FB_OK
    check result.allowed == 1
    check fb_limiter_registry_consume(registry, "global", 6, "global", 6, 1, addr result) == FB_OK
    check result.allowed == 0

    check fb_limiter_registry_add_keyed_fixed_window(
      registry,
      "login",
      5,
      1,
      initDuration(minutes = 1).inNanoseconds,
      16
    ) == FB_OK
    var allowed: int32
    check fb_limiter_registry_allow(registry, "login", 5, "user:1", 6, 1, addr allowed) == FB_OK
    check allowed == 1
    check fb_limiter_registry_allow(registry, "login", 5, "user:1", 6, 1, addr allowed) == FB_OK
    check allowed == 0
    check fb_limiter_registry_allow(registry, "login", 5, "user:2", 6, 1, addr allowed) == FB_OK
    check allowed == 1

    check fb_limiter_registry_add_token_bucket(
      registry,
      "burst",
      5,
      1,
      initDuration(seconds = 1).inNanoseconds,
      1
    ) == FB_OK
    check fb_limiter_registry_consume(registry, "burst", 5, "global", 6, 1, addr result) == FB_OK
    check result.allowed == 1
    check fb_limiter_registry_consume(registry, "burst", 5, "global", 6, 1, addr result) == FB_OK
    check result.allowed == 0

    fb_limiter_registry_destroy(registry)

  test "limiter registry C ABI supports compound limiters":
    var registry: pointer
    check fb_limiter_registry_create(addr registry) == FB_OK
    check fb_limiter_registry_add_keyed_fixed_window(registry, "per_minute", 10, 2, initDuration(minutes = 1).inNanoseconds, 16) == FB_OK
    check fb_limiter_registry_add_keyed_fixed_window(registry, "per_hour", 8, 3, initDuration(hours = 1).inNanoseconds, 16) == FB_OK

    var names = ["per_minute".cstring, "per_hour".cstring]
    var lens = [10.csize_t, 8.csize_t]
    check fb_limiter_registry_add_compound(
      registry,
      "contact",
      7,
      cast[ptr UncheckedArray[cstring]](addr names[0]),
      cast[ptr UncheckedArray[csize_t]](addr lens[0]),
      2
    ) == FB_OK

    var result: FbRateLimitResult
    check fb_limiter_registry_consume(registry, "contact", 7, "user:1", 6, 1, addr result) == FB_OK
    check result.allowed == 1
    check fb_limiter_registry_consume(registry, "contact", 7, "user:1", 6, 1, addr result) == FB_OK
    check result.allowed == 1
    check fb_limiter_registry_consume(registry, "contact", 7, "user:1", 6, 1, addr result) == FB_OK
    check result.allowed == 0
    check fb_limiter_registry_inspect(registry, "contact", 7, "user:2", 6, 1, addr result) == FB_OK
    check result.allowed == 1

    fb_limiter_registry_destroy(registry)

  test "limiter registry C ABI supports stored fixed window callbacks":
    var registry: pointer
    var state = StorageState()
    let storage = FbRateLimitStorage(
      inspectFixedWindow: storageInspect,
      consumeFixedWindow: storageConsume,
      clearFixedWindow: storageClear,
      userData: addr state
    )
    check fb_limiter_registry_create(addr registry) == FB_OK
    check fb_limiter_registry_add_stored_fixed_window(
      registry,
      "stored",
      6,
      "login",
      5,
      2,
      initDuration(minutes = 1).inNanoseconds,
      addr storage,
      64
    ) == FB_OK

    var result: FbRateLimitResult
    check fb_limiter_registry_inspect(registry, "stored", 6, "user:1", 6, 1, addr result) == FB_OK
    check result.allowed == 1
    check state.used == 0
    check state.lastKey == "login:user:1"

    check fb_limiter_registry_consume(registry, "stored", 6, "user:1", 6, 1, addr result) == FB_OK
    check result.allowed == 1
    check state.used == 1
    check fb_limiter_registry_consume(registry, "stored", 6, "user:1", 6, 1, addr result) == FB_OK
    check result.allowed == 1
    check state.used == 2
    check fb_limiter_registry_consume(registry, "stored", 6, "user:1", 6, 1, addr result) == FB_OK
    check result.allowed == 0

    var cleared: int32
    check fb_limiter_registry_clear(registry, "stored", 6, "user:1", 6, addr cleared) == FB_OK
    check cleared == 1
    check state.clearCalls == 1
    check state.used == 0

    fb_limiter_registry_destroy(registry)

  test "limiter registry C ABI reports stored fixed window callback errors":
    var registry: pointer
    var state = StorageState(failStatus: 77)
    let storage = FbRateLimitStorage(
      inspectFixedWindow: storageInspect,
      consumeFixedWindow: storageConsume,
      clearFixedWindow: storageClear,
      userData: addr state
    )
    check fb_limiter_registry_create(addr registry) == FB_OK
    check fb_limiter_registry_add_stored_fixed_window(
      registry,
      "stored",
      6,
      "login",
      5,
      2,
      initDuration(minutes = 1).inNanoseconds,
      addr storage,
      64
    ) == FB_OK

    var result: FbRateLimitResult
    check fb_limiter_registry_consume(registry, "stored", 6, "user:1", 6, 1, addr result) ==
      FB_ERR_INVALID_ARGUMENT

    var invalidStorage = FbRateLimitStorage(
      inspectFixedWindow: nil,
      consumeFixedWindow: storageConsume,
      clearFixedWindow: storageClear,
      userData: addr state
    )
    check fb_limiter_registry_add_stored_fixed_window(
      registry,
      "broken",
      6,
      "broken",
      6,
      2,
      initDuration(minutes = 1).inNanoseconds,
      addr invalidStorage,
      64
    ) == FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_add_stored_fixed_window(
      registry,
      "missing",
      7,
      "missing",
      7,
      2,
      initDuration(minutes = 1).inNanoseconds,
      nil,
      64
    ) == FB_ERR_INVALID_ARGUMENT

    fb_limiter_registry_destroy(registry)

  test "limiter registry C ABI rejects invalid use":
    var result: FbRateLimitResult
    var allowed: int32
    check fb_limiter_registry_create(nil) == FB_ERR_INVALID_ARGUMENT

    var registry: pointer
    check fb_limiter_registry_create(addr registry) == FB_OK
    check fb_limiter_registry_add_fixed_window(nil, "global", 6, 1, initDuration(minutes = 1).inNanoseconds) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_add_fixed_window(registry, nil, 0, 1, initDuration(minutes = 1).inNanoseconds) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_add_fixed_window(registry, " ", 1, 1, initDuration(minutes = 1).inNanoseconds) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_add_fixed_window(registry, "global", 6, 0, initDuration(minutes = 1).inNanoseconds) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_add_fixed_window(registry, "global", 6, 1, initDuration(minutes = 1).inNanoseconds) == FB_OK
    var storageState = StorageState()
    let storage = FbRateLimitStorage(
      inspectFixedWindow: storageInspect,
      consumeFixedWindow: storageConsume,
      clearFixedWindow: storageClear,
      userData: addr storageState
    )
    check fb_limiter_registry_add_stored_fixed_window(nil, "stored", 6, "p", 1, 1, initDuration(minutes = 1).inNanoseconds, addr storage, 64) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_add_stored_fixed_window(registry, nil, 0, "p", 1, 1, initDuration(minutes = 1).inNanoseconds, addr storage, 64) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_add_stored_fixed_window(registry, "stored", 6, nil, 0, 1, initDuration(minutes = 1).inNanoseconds, addr storage, 64) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_add_fixed_window(registry, "global", 6, 1, initDuration(minutes = 1).inNanoseconds) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_consume(registry, "missing", 7, "global", 6, 1, addr result) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_consume(registry, "global", 6, nil, 0, 1, addr result) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_consume(registry, "global", 6, "global", 6, 0, addr result) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_consume(registry, "global", 6, "global", 6, 1, nil) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_allow(registry, "global", 6, "global", 6, 1, nil) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_allow(nil, "global", 6, "global", 6, 1, addr allowed) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_clear(registry, "global", 6, "global", 6, nil) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_limiter_registry_add_compound(registry, "empty", 5, nil, nil, 0) ==
      FB_ERR_INVALID_ARGUMENT
    fb_limiter_registry_destroy(registry)
