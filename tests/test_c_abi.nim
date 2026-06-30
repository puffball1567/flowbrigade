import std/[times, unittest]

import flowbrigade_c

suite "C ABI":
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

  test "C ABI rejects invalid arguments as error codes":
    var result: FbRateLimitResult
    check fb_token_bucket_consume(nil, 1, addr result) == FB_ERR_INVALID_ARGUMENT
    check fb_fixed_window_create(0, initDuration(seconds = 1).inNanoseconds, nil) ==
      FB_ERR_INVALID_ARGUMENT
    check fb_duration_parse(nil, 0, nil) == FB_ERR_INVALID_ARGUMENT
