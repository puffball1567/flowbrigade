# FlowBrigade Specification

This document defines the language-neutral shape of FlowBrigade. The Nim
package is the reference implementation, but the model is intended to be
portable to other languages.

## Duration

Durations are elapsed-time values, not calendar values. Supported units are
`ns`, `us`, `ms`, `s`, `m`, `h`, and `d`. A day is exactly 24 hours.

Implementations should:

- trim surrounding whitespace
- allow whitespace between value/unit pairs
- allow one leading sign
- reject embedded signs
- reject calendar units such as months and years
- reject values that overflow the implementation's signed nanosecond range

## Rate-Limit Result

Rate limiters return the same logical result:

- `allowed`
- `limit`
- `remaining`
- `retryAfter`
- `resetAfter`

`inspect` must not consume capacity. `consume` may consume only when the
decision is allowed.

## Token Bucket

Token bucket limiters allow bursts up to `burst` and refill at `rate` tokens per
`per` duration. Costs must be positive and must not exceed burst capacity.

## Backoff

Backoff policies calculate a delay for a one-based attempt number. Supported
policy shapes are fixed, linear, and exponential. Portable bindings should keep
the attempt number explicit and return an error for attempts lower than one.

## Fixed Window

Fixed window limiters count usage during a window of length `per`. Costs must be
positive and must not exceed the configured window limit.

## Sliding Window

Sliding window limiters smooth fixed-window boundary spikes by weighting the
previous window during the current window. `inspect` must not consume capacity.

## Circuit Breaker

Circuit breakers start closed. Consecutive failures open the circuit once the
failure threshold is reached. After the reset duration elapses, the next allowed
call moves the circuit to half-open. Success closes it; failure reopens it.

## Bulkhead

Bulkheads track permits for concurrent work. `inspect` reports current permit
state, `acquire` consumes one permit when capacity remains, and `release`
returns one permit. Releasing without an acquired permit is an error.

## Timeout And Deadline

Timeouts track elapsed time from construction. Deadlines track a monotonic end
point. Portable bindings should expose `expired`, `remaining`, and elapsed or
clamp helpers without attempting to cancel running work.

## Budget Ledger

Budget ledgers track per-key usage over a fixed period. `inspect` reports the
decision without mutation, `consume` records allowed usage, `refund` subtracts
usage without going below zero, and reset helpers clear one key or the whole
ledger. Portable bindings should copy caller-owned key bytes during the call and
avoid storing foreign string pointers.

## Locks

Locks use a key, TTL, and lease token. Acquiring an already-held key returns a
non-acquired lease result. Releasing by lease must not clear a newer lock with a
different token. Portable bindings should keep lease tokens behind language-owned
or opaque handles and expose explicit lease cleanup.

## Throttle And Debounce

Throttles allow the first action immediately, then deny repeated actions until
the interval has elapsed or the throttle is reset. Debouncers track pending work
after a call, become ready after a quiet delay, and clear pending state when
ready work is consumed or canceled.

## Retry Callback ABI

Portable callback ABIs should treat operation failure as retry state, not as an
ABI transport failure. A successful callback returns the ABI success status.
Other callback status values are recorded as operation failures until attempts
are exhausted. Sleep callbacks are optional and receive the computed backoff
delay before the next attempt.

## Fallback Callback ABI

Fallback callback ABIs should try ordered providers until one returns the ABI
success status. Provider failures and exhausted provider lists are result state,
not ABI transport failures. Optional predicates can stop fallback after a
provider failure. Optional circuit breaker handles can skip open providers and
record provider failure or success.

## Limiter Registry ABI

Limiter registry ABIs should expose named limiter definitions and named
inspection/consumption operations. Compound limiters reference existing child
names and inspect before consuming children so a denied compound decision does
not partially consume capacity.

Stored fixed-window registry entries may be backed by callback storage. The
callback owns atomic storage semantics; the ABI boundary owns string copying,
input validation, fixed result structs, and error-code conversion.

Metric export ABIs should keep exporters backend-neutral. They convert stable
decision structs into caller-owned text buffers without retaining pointers or
starting background work.

## ABI Boundary

Portable bindings should avoid language-specific memory ownership crossing the
boundary. The C ABI uses opaque handles, fixed structs, caller-owned buffers,
integer status codes, ABI version and feature reporting, and diagnostic error
text.
