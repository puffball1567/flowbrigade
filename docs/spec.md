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

## Fixed Window

Fixed window limiters count usage during a window of length `per`. Costs must be
positive and must not exceed the configured window limit.

## Circuit Breaker

Circuit breakers start closed. Consecutive failures open the circuit once the
failure threshold is reached. After the reset duration elapses, the next allowed
call moves the circuit to half-open. Success closes it; failure reopens it.

## ABI Boundary

Portable bindings should avoid language-specific memory ownership crossing the
boundary. The C ABI uses opaque handles, fixed structs, caller-owned buffers, and
integer status codes.
