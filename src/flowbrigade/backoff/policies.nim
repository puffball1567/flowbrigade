import std/[random, times]

import ./jitter

type
  BackoffError* = object of ValueError
  BackoffConfigError* = object of ValueError

  BackoffKind = enum
    bkFixed, bkLinear, bkExponential

  BackoffPolicy* = object
    kind: BackoffKind
    initial: Duration
    increment: Duration
    factor: float
    maxDelay: Duration
    jitter: JitterKind

proc ensurePositive(name: string; value: Duration) =
  if value <= initDuration():
    raise newException(BackoffConfigError, name & " must be positive")

proc ensureMaxAtLeastInitial(initial, maxDelay: Duration) =
  if maxDelay < initial:
    raise newException(BackoffConfigError, "maxDelay must be greater than or equal to initial")

proc ensureAttempt(attempt: int) =
  if attempt < 1:
    raise newException(BackoffError, "attempt must be at least 1")

proc fixedBackoff*(delay: Duration; jitter = noJitter): BackoffPolicy =
  ensurePositive("delay", delay)
  BackoffPolicy(kind: bkFixed, initial: delay, maxDelay: delay, jitter: jitter)

proc linearBackoff*(
    initial, increment, maxDelay: Duration;
    jitter = noJitter
): BackoffPolicy =
  ensurePositive("initial", initial)
  ensurePositive("increment", increment)
  ensurePositive("maxDelay", maxDelay)
  ensureMaxAtLeastInitial(initial, maxDelay)
  BackoffPolicy(
    kind: bkLinear,
    initial: initial,
    increment: increment,
    maxDelay: maxDelay,
    jitter: jitter
  )

proc expBackoff*(
    initial: Duration;
    factor: float;
    maxDelay: Duration;
    jitter = noJitter
): BackoffPolicy =
  ensurePositive("initial", initial)
  ensurePositive("maxDelay", maxDelay)
  ensureMaxAtLeastInitial(initial, maxDelay)
  if factor <= 1.0:
    raise newException(BackoffConfigError, "factor must be greater than 1")
  BackoffPolicy(
    kind: bkExponential,
    initial: initial,
    factor: factor,
    maxDelay: maxDelay,
    jitter: jitter
  )

proc durationFromNanos(nanos: int64): Duration =
  initDuration(nanoseconds = nanos)

proc capDelay(delay, maxDelay: Duration): Duration =
  if delay > maxDelay: maxDelay else: delay

proc randDuration(minDelay, maxDelay: Duration): Duration =
  let minNanos = minDelay.inNanoseconds
  let maxNanos = maxDelay.inNanoseconds
  if maxNanos <= minNanos:
    return minDelay
  durationFromNanos(rand(maxNanos - minNanos) + minNanos)

proc baseDelay(policy: BackoffPolicy; attempt: int): Duration =
  case policy.kind
  of bkFixed:
    policy.initial
  of bkLinear:
    let remaining = policy.maxDelay - policy.initial
    let stepsToCap = remaining.inNanoseconds div policy.increment.inNanoseconds
    if int64(attempt - 1) >= stepsToCap:
      return policy.maxDelay
    capDelay(
      policy.initial + initDuration(
        nanoseconds = policy.increment.inNanoseconds * int64(attempt - 1)
      ),
      policy.maxDelay
    )
  of bkExponential:
    var nanos = float(policy.initial.inNanoseconds)
    for _ in 2 .. attempt:
      nanos *= policy.factor
      if nanos >= float(policy.maxDelay.inNanoseconds):
        return policy.maxDelay
    capDelay(durationFromNanos(int64(nanos)), policy.maxDelay)

proc delayFor*(policy: BackoffPolicy; attempt: int): Duration =
  ensureAttempt(attempt)
  let base = policy.baseDelay(attempt)
  case policy.jitter
  of noJitter:
    base
  of fullJitter:
    randDuration(initDuration(), base)
  of equalJitter:
    randDuration(durationFromNanos(base.inNanoseconds div 2), base)
  of decorrelatedJitter:
    randDuration(policy.initial, policy.maxDelay)
