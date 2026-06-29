import flowbrigade

var registry = initLimiterRegistry()

registry.addLimiter("login", keyedFixedWindowDefinition(
  limit = 2,
  per = 1.min
))
registry.addLimiter("account", keyedFixedWindowDefinition(
  limit = 3,
  per = 1.hr
))
registry.addCompoundLimiter("login_guard", ["login", "account"])

let first = registry.consume("login_guard", key = "account:42")
let second = registry.consume("login_guard", key = "account:42")
let third = registry.consume("login_guard", key = "account:42")

doAssert first.allowed
doAssert second.allowed
doAssert not third.allowed

type RequestShape = object
  accountId: string
  action: string

let extractor = initKeyExtractor[RequestShape]()
  .withPart(proc(request: RequestShape): string = request.accountId)
  .withPart(proc(request: RequestShape): string = request.action)

let key = extractor.extract(RequestShape(accountId: "7", action: "password-reset"))
discard registry.consume("login_guard", key = key)
discard registry.consume("login_guard", key = key)
let decision = registry.consume("login_guard", key = key)
let http = httpLimitDecision(decision)

doAssert http.statusCode == 429
