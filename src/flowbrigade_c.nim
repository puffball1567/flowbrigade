import std/times

import flowbrigade/circuit_breaker
import flowbrigade/durations
import flowbrigade/ratelimit

const
  FB_OK* = 0.cint
  FB_ERR_INVALID_ARGUMENT* = 1.cint
  FB_ERR_BUFFER_TOO_SMALL* = 2.cint
  FB_ERR_INTERNAL* = 100.cint

  FB_CIRCUIT_CLOSED* = 0.cint
  FB_CIRCUIT_OPEN* = 1.cint
  FB_CIRCUIT_HALF_OPEN* = 2.cint

type
  FbRateLimitResult* {.bycopy.} = object
    allowed*: int32
    limit*: int32
    remaining*: int32
    retryAfterNs*: int64
    resetAfterNs*: int64

  TokenBucketHandle = ref object
    limiter: TokenBucket

  FixedWindowHandle = ref object
    limiter: FixedWindow

  CircuitBreakerHandle = ref object
    breaker: CircuitBreaker

proc durationFromNanos(nanos: int64): Duration =
  initDuration(nanoseconds = nanos)

proc copyInput(input: cstring; inputLen: csize_t): string =
  if inputLen == 0:
    return ""
  result = newString(int(inputLen))
  copyMem(addr result[0], input, int(inputLen))

proc writeRateLimitResult(outResult: ptr FbRateLimitResult; decision: RateLimitResult): cint =
  if outResult.isNil:
    return FB_ERR_INVALID_ARGUMENT
  outResult[] = FbRateLimitResult(
    allowed: (if decision.allowed: 1'i32 else: 0'i32),
    limit: int32(decision.limit),
    remaining: int32(decision.remaining),
    retryAfterNs: decision.retryAfter.inNanoseconds,
    resetAfterNs: decision.resetAfter.inNanoseconds
  )
  FB_OK

template catchAbiErrors(body: untyped): cint =
  try:
    body
  except ValueError:
    FB_ERR_INVALID_ARGUMENT
  except CatchableError:
    FB_ERR_INTERNAL

proc fb_duration_parse*(
    input: cstring;
    inputLen: csize_t;
    outNs: ptr int64
): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if input.isNil or outNs.isNil:
      return FB_ERR_INVALID_ARGUMENT
    outNs[] = parseDuration(copyInput(input, inputLen)).inNanoseconds
    FB_OK

proc fb_duration_format*(
    durationNs: int64;
    buffer: cstring;
    bufferLen: csize_t;
    outLen: ptr csize_t
): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if outLen.isNil:
      return FB_ERR_INVALID_ARGUMENT
    let text = formatDuration(durationFromNanos(durationNs))
    outLen[] = csize_t(text.len)
    if buffer.isNil or bufferLen <= csize_t(text.len):
      return FB_ERR_BUFFER_TOO_SMALL
    let outBuffer = cast[ptr UncheckedArray[char]](buffer)
    copyMem(addr outBuffer[0], cstring(text), text.len)
    outBuffer[text.len] = '\0'
    FB_OK

proc fb_token_bucket_create*(
    rate: int32;
    perNs: int64;
    burst: int32;
    outHandle: ptr pointer
): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if outHandle.isNil:
      return FB_ERR_INVALID_ARGUMENT
    let handle = TokenBucketHandle(
      limiter: initTokenBucket(int(rate), durationFromNanos(perNs), int(burst))
    )
    GC_ref(handle)
    outHandle[] = cast[pointer](handle)
    FB_OK

proc fb_token_bucket_destroy*(handle: pointer) {.cdecl, exportc, dynlib.} =
  if not handle.isNil:
    GC_unref(cast[TokenBucketHandle](handle))

proc fb_token_bucket_inspect*(
    handle: pointer;
    cost: int32;
    outResult: ptr FbRateLimitResult
): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if handle.isNil:
      return FB_ERR_INVALID_ARGUMENT
    var state = cast[TokenBucketHandle](handle)
    writeRateLimitResult(outResult, state.limiter.inspect(int(cost)))

proc fb_token_bucket_consume*(
    handle: pointer;
    cost: int32;
    outResult: ptr FbRateLimitResult
): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if handle.isNil:
      return FB_ERR_INVALID_ARGUMENT
    var state = cast[TokenBucketHandle](handle)
    writeRateLimitResult(outResult, state.limiter.consume(int(cost)))

proc fb_fixed_window_create*(
    limit: int32;
    perNs: int64;
    outHandle: ptr pointer
): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if outHandle.isNil:
      return FB_ERR_INVALID_ARGUMENT
    let handle = FixedWindowHandle(
      limiter: initFixedWindow(int(limit), durationFromNanos(perNs))
    )
    GC_ref(handle)
    outHandle[] = cast[pointer](handle)
    FB_OK

proc fb_fixed_window_destroy*(handle: pointer) {.cdecl, exportc, dynlib.} =
  if not handle.isNil:
    GC_unref(cast[FixedWindowHandle](handle))

proc fb_fixed_window_inspect*(
    handle: pointer;
    cost: int32;
    outResult: ptr FbRateLimitResult
): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if handle.isNil:
      return FB_ERR_INVALID_ARGUMENT
    var state = cast[FixedWindowHandle](handle)
    writeRateLimitResult(outResult, state.limiter.inspect(int(cost)))

proc fb_fixed_window_consume*(
    handle: pointer;
    cost: int32;
    outResult: ptr FbRateLimitResult
): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if handle.isNil:
      return FB_ERR_INVALID_ARGUMENT
    var state = cast[FixedWindowHandle](handle)
    writeRateLimitResult(outResult, state.limiter.consume(int(cost)))

proc fb_circuit_breaker_create*(
    failureThreshold: int32;
    resetAfterNs: int64;
    outHandle: ptr pointer
): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if outHandle.isNil:
      return FB_ERR_INVALID_ARGUMENT
    let handle = CircuitBreakerHandle(
      breaker: initCircuitBreaker(int(failureThreshold), durationFromNanos(resetAfterNs))
    )
    GC_ref(handle)
    outHandle[] = cast[pointer](handle)
    FB_OK

proc fb_circuit_breaker_destroy*(handle: pointer) {.cdecl, exportc, dynlib.} =
  if not handle.isNil:
    GC_unref(cast[CircuitBreakerHandle](handle))

proc fb_circuit_breaker_allow*(
    handle: pointer;
    outAllowed: ptr int32
): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if handle.isNil or outAllowed.isNil:
      return FB_ERR_INVALID_ARGUMENT
    var state = cast[CircuitBreakerHandle](handle)
    outAllowed[] = (if state.breaker.allow(): 1'i32 else: 0'i32)
    FB_OK

proc fb_circuit_breaker_record_success*(handle: pointer): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if handle.isNil:
      return FB_ERR_INVALID_ARGUMENT
    var state = cast[CircuitBreakerHandle](handle)
    state.breaker.recordSuccess()
    FB_OK

proc fb_circuit_breaker_record_failure*(handle: pointer): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if handle.isNil:
      return FB_ERR_INVALID_ARGUMENT
    var state = cast[CircuitBreakerHandle](handle)
    state.breaker.recordFailure()
    FB_OK

proc fb_circuit_breaker_state*(
    handle: pointer;
    outState: ptr int32
): cint {.cdecl, exportc, dynlib.} =
  catchAbiErrors:
    if handle.isNil or outState.isNil:
      return FB_ERR_INVALID_ARGUMENT
    let state = cast[CircuitBreakerHandle](handle).breaker.state()
    outState[] = case state
      of circuitClosed: FB_CIRCUIT_CLOSED
      of circuitOpen: FB_CIRCUIT_OPEN
      of circuitHalfOpen: FB_CIRCUIT_HALF_OPEN
    FB_OK
