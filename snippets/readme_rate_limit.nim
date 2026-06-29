import std/times

import flowbrigade

var limiter = initTokenBucket(
  rate = 10,
  per = initDuration(seconds = 1),
  burst = 20
)

doAssert limiter.allow()
let result = limiter.consume()
doAssert result.allowed
