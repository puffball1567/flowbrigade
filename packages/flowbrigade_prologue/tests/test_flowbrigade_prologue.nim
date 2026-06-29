import std/[httpcore, os, strtabs, unittest, uri]

import cookiejar
import flowbrigade
import flowbrigade/internal/time_source
import flowbrigade_prologue
import prologue
import prologue/mocking

proc hello(ctx: Context) {.async.} =
  resp "ok"

proc request(
    path = "/";
    httpMethod = HttpGet;
    headers = newHttpHeaders();
    cookies = initCookieJar();
    queryParams = newStringTable();
    pathParams = newStringTable()
): Request =
  result = initMockingRequest(
    httpMethod = httpMethod,
    headers = headers,
    url = parseUri(path),
    cookies = cookies,
    postParams = newStringTable(),
    queryParams = newStringTable(),
    formParams = initFormPart(),
    pathParams = pathParams
  )
  result.queryParams = queryParams

suite "Prologue FlowBrigade bridge":
  test "rate limit middleware allows requests and attaches headers":
    let policy = apiAbuseProtectionPolicy(
      perIdentityLimit = 2,
      perIdentityWindow = 1.min,
      globalRate = 10,
      globalPer = 1.sec,
      globalBurst = 10
    )
    var app = newApp()
    app.mockApp()
    app.use(rateLimitMiddleware(policy, pathKey()))
    app.addRoute("/", hello)

    let ctx = app.runOnce(request("/"))

    check ctx.response.code == Http200
    check ctx.response.body == "ok"
    check ctx.response.hasHeader("RateLimit-Limit")
    check ctx.response.hasHeader("RateLimit-Remaining")

  test "rate limit middleware denies over-limit requests":
    let policy = apiAbuseProtectionPolicy(
      perIdentityLimit = 1,
      perIdentityWindow = 1.min,
      globalRate = 10,
      globalPer = 1.sec,
      globalBurst = 10
    )
    var app = newApp()
    app.mockApp()
    app.use(rateLimitMiddleware(policy, pathKey(), deniedBody = "slow down"))
    app.addRoute("/", hello)

    discard app.runOnce(request("/"))
    let denied = app.runOnce(request("/"))

    check denied.response.code == HttpCode(429)
    check denied.response.body == "slow down"
    check denied.response.hasHeader("Retry-After")

  test "header key isolates callers":
    let policy = loginProtectionPolicy(
      accountLimit = 1,
      accountWindow = 1.min,
      identityLimit = 10,
      identityWindow = 1.hr
    )
    var app = newApp()
    app.mockApp()
    app.use(rateLimitMiddleware(policy, headerKey("X-Account-ID")))
    app.addRoute("/", hello)

    var aliceHeaders = newHttpHeaders()
    aliceHeaders["X-Account-ID"] = "alice"
    var bobHeaders = newHttpHeaders()
    bobHeaders["X-Account-ID"] = "bob"

    check app.runOnce(request("/", headers = aliceHeaders)).response.code == Http200
    check app.runOnce(request("/", headers = aliceHeaders)).response.code == HttpCode(429)
    check app.runOnce(request("/", headers = bobHeaders)).response.code == Http200

  test "registry middleware consumes named limiter":
    var registry = initLimiterRegistry()
    registry.addLimiter("api", keyedFixedWindowDefinition(limit = 1, per = 1.min))
    var app = newApp()
    app.mockApp()
    app.use(rateLimitMiddleware(registry, "api", methodPathKey()))
    app.addRoute("/", hello)

    check app.runOnce(request("/")).response.code == Http200
    check app.runOnce(request("/")).response.code == HttpCode(429)

  test "query parameter key isolates callers":
    let policy = loginProtectionPolicy(
      accountLimit = 1,
      accountWindow = 1.min,
      identityLimit = 10,
      identityWindow = 1.hr
    )
    var app = newApp()
    app.mockApp()
    app.use(rateLimitMiddleware(policy, queryParamKey("tenant")))
    app.addRoute("/", hello)

    var acme = newStringTable()
    acme["tenant"] = "acme"
    var beta = newStringTable()
    beta["tenant"] = "beta"

    check app.runOnce(request("/", queryParams = acme)).response.code == Http200
    check app.runOnce(request("/", queryParams = acme)).response.code == HttpCode(429)
    check app.runOnce(request("/", queryParams = beta)).response.code == Http200

  test "path parameter and cookie keys can compose stable keys":
    let policy = loginProtectionPolicy(
      accountLimit = 1,
      accountWindow = 1.min,
      identityLimit = 10,
      identityWindow = 1.hr
    )
    var app = newApp()
    app.mockApp()
    app.use(rateLimitMiddleware(policy, compoundKey("tenant", [
      pathParamKey("tenant_id"),
      cookieKey("session_id")
    ])))
    app.addRoute("/", hello)

    var acmePath = newStringTable()
    acmePath["tenant_id"] = "acme"
    var betaPath = newStringTable()
    betaPath["tenant_id"] = "beta"
    var cookies = initCookieJar()
    cookies["session_id"] = "session-1"

    check app.runOnce(request("/", pathParams = acmePath, cookies = cookies)).response.code == Http200
    check app.runOnce(request("/", pathParams = acmePath, cookies = cookies)).response.code == HttpCode(429)
    check app.runOnce(request("/", pathParams = betaPath, cookies = cookies)).response.code == Http200

  test "middleware can limit only selected methods":
    let policy = apiAbuseProtectionPolicy(
      perIdentityLimit = 1,
      perIdentityWindow = 1.min,
      globalRate = 10,
      globalPer = 1.sec,
      globalBurst = 10
    )
    var app = newApp()
    app.mockApp()
    app.use(rateLimitMiddleware(
      policy,
      pathKey(),
      allowedMethods = {HttpPost}
    ))
    app.get("/", hello)
    app.post("/", hello)

    check app.runOnce(request("/", httpMethod = HttpGet)).response.code == Http200
    check app.runOnce(request("/", httpMethod = HttpGet)).response.code == Http200
    check app.runOnce(request("/", httpMethod = HttpPost)).response.code == Http200
    check app.runOnce(request("/", httpMethod = HttpPost)).response.code == HttpCode(429)

  test "middleware can omit headers and set custom content type":
    let policy = apiAbuseProtectionPolicy(
      perIdentityLimit = 1,
      perIdentityWindow = 1.min,
      globalRate = 10,
      globalPer = 1.sec,
      globalBurst = 10
    )
    var app = newApp()
    app.mockApp()
    app.use(rateLimitMiddleware(
      policy,
      pathKey(),
      deniedBody = """{"error":"limited"}""",
      headerMode = noRateLimitHeaders,
      contentType = "application/json"
    ))
    app.addRoute("/", hello)

    discard app.runOnce(request("/"))
    let denied = app.runOnce(request("/"))
    check denied.response.code == HttpCode(429)
    check denied.response.body == """{"error":"limited"}"""
    check not denied.response.hasHeader("RateLimit-Limit")
    check denied.response.getHeader("Content-Type")[0] == "application/json"

  test "thread-safe policy overload works as middleware":
    let policy = initThreadSafeFlowPolicy(apiAbuseProtectionPolicy(
      perIdentityLimit = 1,
      perIdentityWindow = 1.min,
      globalRate = 10,
      globalPer = 1.sec,
      globalBurst = 10
    ))
    var app = newApp()
    app.mockApp()
    app.use(rateLimitMiddleware(policy, pathKey()))
    app.addRoute("/", hello)

    check app.runOnce(request("/")).response.code == Http200
    check app.runOnce(request("/")).response.code == HttpCode(429)

  test "config file builds API abuse middleware":
    let configPath = getTempDir() / "flowbrigade-prologue-api.ini"
    writeFile(configPath, """
[rate_limit]
policy = api_abuse
backend = thread_safe_memory
key = header
key_name = X-Account-ID
allowed_methods = POST
per_identity_limit = 1
per_identity_window = 1m
global_rate = 10
global_per = 1s
global_burst = 10
denied_body = configured limit
header_mode = none
""")
    defer: removeFile(configPath)

    var app = newApp()
    app.mockApp()
    app.use(prologueRateLimitMiddlewareFromFile(configPath))
    app.get("/", hello)
    app.post("/", hello)

    var headers = newHttpHeaders()
    headers["X-Account-ID"] = "alice"

    check app.runOnce(request("/", httpMethod = HttpGet, headers = headers)).response.code == Http200
    check app.runOnce(request("/", httpMethod = HttpGet, headers = headers)).response.code == Http200
    check app.runOnce(request("/", httpMethod = HttpPost, headers = headers)).response.code == Http200
    let denied = app.runOnce(request("/", httpMethod = HttpPost, headers = headers))
    check denied.response.code == HttpCode(429)
    check denied.response.body == "configured limit"
    check not denied.response.hasHeader("RateLimit-Limit")

  test "config file builds login guard middleware":
    let configPath = getTempDir() / "flowbrigade-prologue-login.ini"
    writeFile(configPath, """
[login_guard]
policy = login
backend = memory
account_key = header
account_key_name = X-Account-ID
identity_key = header
identity_key_name = X-Client-ID
account_limit = 1
account_window = 1m
identity_limit = 10
identity_window = 1h
denied_body = configured login limit
""")
    defer: removeFile(configPath)

    var app = newApp()
    app.mockApp()
    app.use(prologueRateLimitMiddlewareFromFile(configPath, "login_guard"))
    app.addRoute("/", hello)

    var headers = newHttpHeaders()
    headers["X-Account-ID"] = "alice"
    headers["X-Client-ID"] = "client-1"

    check app.runOnce(request("/", headers = headers)).response.code == Http200
    let denied = app.runOnce(request("/", headers = headers))
    check denied.response.code == HttpCode(429)
    check denied.response.body == "configured login limit"

  test "login guard middleware combines account and identity keys":
    let policy = loginProtectionPolicy(
      accountLimit = 1,
      accountWindow = 1.min,
      identityLimit = 10,
      identityWindow = 1.hr
    )
    var app = newApp()
    app.mockApp()
    app.use(loginGuardMiddleware(
      policy,
      accountKey = headerKey("X-Account-ID"),
      identityKey = headerKey("X-Client-ID")
    ))
    app.addRoute("/", hello)

    var aliceClientOne = newHttpHeaders()
    aliceClientOne["X-Account-ID"] = "alice"
    aliceClientOne["X-Client-ID"] = "client-1"
    var aliceClientTwo = newHttpHeaders()
    aliceClientTwo["X-Account-ID"] = "alice"
    aliceClientTwo["X-Client-ID"] = "client-2"

    check app.runOnce(request("/", headers = aliceClientOne)).response.code == Http200
    check app.runOnce(request("/", headers = aliceClientOne)).response.code == HttpCode(429)
    check app.runOnce(request("/", headers = aliceClientTwo)).response.code == Http200

  test "password reset guard middleware has its own default denial body":
    let policy = passwordResetProtectionPolicy(
      accountLimit = 1,
      accountWindow = 1.min,
      identityLimit = 10,
      identityWindow = 1.hr
    )
    var app = newApp()
    app.mockApp()
    app.use(passwordResetGuardMiddleware(
      policy,
      accountKey = headerKey("X-Account-ID"),
      identityKey = headerKey("X-Client-ID")
    ))
    app.addRoute("/", hello)

    var headers = newHttpHeaders()
    headers["X-Account-ID"] = "alice"
    headers["X-Client-ID"] = "client-1"

    discard app.runOnce(request("/", headers = headers))
    let denied = app.runOnce(request("/", headers = headers))

    check denied.response.code == HttpCode(429)
    check denied.response.body == "Too many password reset attempts"

  test "deadline middleware continues before expiry and denies after expiry":
    let time = initManualTimeSource()
    let deadline = initDeadline(after = 10.sec, timeSource = time)
    var app = newApp()
    app.mockApp()
    app.use(deadlineMiddleware(deadline))
    app.addRoute("/", hello)

    let allowed = app.runOnce(request("/"))
    check allowed.response.code == Http200
    check allowed.response.body == "ok"
    check allowed.response.hasHeader("X-FlowBrigade-Deadline-Remaining-Ms")

    time.advance(10.sec)
    let denied = app.runOnce(request("/"))

    check denied.response.code == HttpCode(504)
    check denied.response.body == "Deadline expired"

  test "configuration rejects missing values":
    let policy = apiAbuseProtectionPolicy()

    expect PrologueBridgeConfigError:
      discard headerKey(" ")
    expect PrologueBridgeConfigError:
      discard queryParamKey(" ")
    expect PrologueBridgeConfigError:
      discard compoundKey("tenant", [])
    expect PrologueBridgeConfigError:
      discard compoundKey("tenant", [PrologueRateLimitKeyProc(nil)])
    expect PrologueBridgeConfigError:
      discard rateLimitMiddleware(policy, nil)
    expect PrologueBridgeConfigError:
      discard rateLimitMiddleware(initLimiterRegistry(), " ", pathKey())
    expect PrologueBridgeConfigError:
      discard authAttemptKey(" ", pathKey(), methodPathKey())
    expect PrologueConfigError:
      discard prologueRateLimitMiddlewareFromFile("/tmp/flowbrigade-missing-config.ini")
