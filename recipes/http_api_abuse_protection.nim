import flowbrigade

type ApiRequest = object
  routeId: string
  accountId: string
  ip: string

var registry = initLimiterRegistry()
registry.addLimiter("anonymous_route", keyedFixedWindowDefinition(
  limit = 60,
  per = 1.min,
  maxKeys = 50_000
))
registry.addLimiter("account_route", keyedFixedWindowDefinition(
  limit = 600,
  per = 1.min,
  maxKeys = 50_000
))

let anonymousKey = initKeyExtractor[ApiRequest]()
  .withPart(proc(request: ApiRequest): string = "anon")
  .withPart(proc(request: ApiRequest): string = request.ip)
  .withPart(proc(request: ApiRequest): string = request.routeId)

let accountKey = initKeyExtractor[ApiRequest]()
  .withPart(proc(request: ApiRequest): string = "account")
  .withPart(proc(request: ApiRequest): string = request.accountId)
  .withPart(proc(request: ApiRequest): string = request.routeId)

proc protectApi(request: ApiRequest): HttpLimitDecision =
  let isAuthenticated = request.accountId.len > 0
  let limiterName = if isAuthenticated: "account_route" else: "anonymous_route"
  let key =
    if isAuthenticated:
      accountKey.extract(request)
    else:
      anonymousKey.extract(request)

  registry.consume(limiterName, key = key).httpLimitDecision(
    deniedStatusCode = 429,
    deniedBody = "Too many requests"
  )

let request = ApiRequest(routeId: "get-v1-search", ip: "203.0.113.10")
let first = protectApi(request)

doAssert first.allowed
doAssert first.statusCode == 200

for _ in 1 .. 60:
  discard protectApi(request)

let blocked = protectApi(request)
doAssert not blocked.allowed
doAssert blocked.statusCode == 429
doAssert ("Retry-After", "60") in blocked.headers
