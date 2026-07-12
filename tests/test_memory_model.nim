import std/unittest
import std/times
import flowbrigade

suite "memory model":
  test "uses Nim ARC memory manager":
    when defined(gcArc):
      check true
    else:
      check false

  test "creates and releases common limiter values under ARC":
    var allowed = 0
    for i in 0 ..< 200:
      var limiter = initTokenBucket(rate = 10, per = initDuration(seconds = 1), burst = 20)
      if limiter.allow():
        inc allowed
      var keyed = initKeyedFixedWindow[string](limit = 2, per = initDuration(seconds = 1), maxKeys = 32)
      check keyed.allow("tenant-" & $i)
    check allowed == 200
