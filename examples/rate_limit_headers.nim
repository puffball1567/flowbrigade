import flowbrigade

var limiter = initFixedWindow(limit = 2, per = 1.sec)

discard limiter.consume()
discard limiter.consume()
let denied = limiter.consume()

doAssert not denied.allowed

for header in rateLimitHeaders(denied):
  echo header.name, ": ", header.value
