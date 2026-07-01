import std/[strutils, times]

import flowbrigade

const Iterations = 100_000

template bench(name: string; body: untyped) =
  block:
    let started = cpuTime()
    body
    let elapsed = cpuTime() - started
    echo name, ": ", elapsed.formatFloat(ffDecimal, 6), "s"

bench "parseDuration 100k":
  var total = initDuration()
  for _ in 0 ..< Iterations:
    total += parseDuration("1h30m250ms")
  doAssert total > initDuration()

bench "token bucket consume 100k":
  var limiter = initTokenBucket(rate = Iterations, per = 1.sec, burst = Iterations)
  var allowed = 0
  for _ in 0 ..< Iterations:
    if limiter.allow():
      inc allowed
  doAssert allowed == Iterations

bench "GCRA consume 100k":
  var limiter = initGcraLimiter(rate = Iterations, per = 1.sec, burst = Iterations)
  var allowed = 0
  for _ in 0 ..< Iterations:
    if limiter.allow():
      inc allowed
  doAssert allowed == Iterations

bench "keyed GCRA consume 100k":
  var limiter = initKeyedGcraLimiter[string](rate = Iterations, per = 1.sec, burst = Iterations)
  var allowed = 0
  for i in 0 ..< Iterations:
    if limiter.allow("user-" & $(i mod 100)):
      inc allowed
  doAssert allowed == Iterations

bench "fixed window consume 100k":
  var limiter = initFixedWindow(limit = Iterations, per = 1.sec)
  var allowed = 0
  for _ in 0 ..< Iterations:
    if limiter.allow():
      inc allowed
  doAssert allowed == Iterations

bench "sliding window consume 100k":
  var limiter = initSlidingWindow(limit = Iterations, per = 1.sec)
  var allowed = 0
  for _ in 0 ..< Iterations:
    if limiter.allow():
      inc allowed
  doAssert allowed == Iterations
