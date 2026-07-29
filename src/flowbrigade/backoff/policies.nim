import std/[random, times]

import ./jitter

type
  BackoffError* = object of ValueError
  BackoffConfigError* = object of ValueError
  RandomIntProc* = proc(upperExclusive: int64): int64 {.closure.}

  DecorrelatedJitterState = ref object
    previous: Duration

  BackoffKind = enum
    bkFixed, bkLinear, bkExponential

  BackoffPolicy* = object
    kind: BackoffKind
    initial: Duration
    increment: Duration
    factor: float
    maxDelay: Duration
    jitter: JitterKind
    randomSource: RandomIntProc
    decorrelatedState: DecorrelatedJitterState

proc ensurePositive(name: string; value: Duration) =
  if value <= initDuration():
    raise newException(BackoffConfigError, name & " must be positive")

proc ensureMaxAtLeastInitial(initial, maxDelay: Duration) =
  if maxDelay < initial:
    raise newException(BackoffConfigError, "maxDelay must be greater than or equal to initial")

proc ensureAttempt(attempt: int) =
  if attempt < 1:
    raise newException(BackoffError, "attempt must be at least 1")

proc fixedBackoff*(
    delay: Duration;
    jitter = noJitter;
    randomSource: RandomIntProc = nil
): BackoffPolicy =
  ensurePositive("delay", delay)
  BackoffPolicy(
    kind: bkFixed, initial: delay, maxDelay: delay, jitter: jitter,
    randomSource: randomSource, decorrelatedState: DecorrelatedJitterState(previous: delay)
  )

proc linearBackoff*(
    initial, increment, maxDelay: Duration;
    jitter = noJitter;
    randomSource: RandomIntProc = nil
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
    jitter: jitter,
    randomSource: randomSource,
    decorrelatedState: DecorrelatedJitterState(previous: initial)
  )

proc expBackoff*(
    initial: Duration;
    factor: float;
    maxDelay: Duration;
    jitter = noJitter;
    randomSource: RandomIntProc = nil
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
    jitter: jitter,
    randomSource: randomSource,
    decorrelatedState: DecorrelatedJitterState(previous: initial)
  )

proc durationFromNanos(nanos: int64): Duration =
  initDuration(nanoseconds = nanos)

proc capDelay(delay, maxDelay: Duration): Duration =
  if delay > maxDelay: maxDelay else: delay

proc defaultRandomInt(upperExclusive: int64): int64 =
  if upperExclusive <= 1:
    return 0
  rand(upperExclusive - 1)

proc randDuration(policy: BackoffPolicy; minDelay, maxDelay: Duration): Duration =
  let minNanos = minDelay.inNanoseconds
  let maxNanos = maxDelay.inNanoseconds
  if maxNanos <= minNanos:
    return minDelay
  let span = maxNanos - minNanos + 1
  let source = if policy.randomSource.isNil: defaultRandomInt else: policy.randomSource
  let value = source(span)
  durationFromNanos(minNanos + max(0'i64, min(value, span - 1)))

proc resetJitter*(policy: BackoffPolicy) =
  ## Resets the state retained by decorrelated jitter.
  policy.decorrelatedState.previous = policy.initial

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
    result = base
  of fullJitter:
    result = policy.randDuration(initDuration(), base)
  of equalJitter:
    result = policy.randDuration(durationFromNanos(base.inNanoseconds div 2), base)
  of decorrelatedJitter:
    let previous = policy.decorrelatedState.previous
    let upper = capDelay(
      durationFromNanos(previous.inNanoseconds * 3),
      policy.maxDelay
    )
    result = policy.randDuration(policy.initial, upper)
    policy.decorrelatedState.previous = result
