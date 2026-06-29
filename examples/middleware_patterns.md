# Middleware patterns

FlowBrigade does not ship framework middleware in the core package. Framework
integration should stay thin: build a key, consume a limiter, attach headers,
and either continue or return a denial response.

## Generic HTTP shape

```nim
import pkg/flowbrigade

var limiter = initFixedWindow(limit = 100, per = 1.min)

proc handleRequest(request: Request): Response =
  let decision = limiter.consume()
  if not decision.allowed:
    return response(
      status = 429,
      headers = rateLimitHeadersTable(decision),
      body = "rate limit exceeded"
    )

  let res = nextHandler(request)
  for header in rateLimitHeaders(decision):
    res.headers[header.name] = header.value
  res
```

## Keyed route/user shape

```nim
let key = rateLimitKey([request.routeName, request.userId])
let decision = storedLimiter.consume(key)
```

Use `opaqueRateLimitKey` with an application-provided HMAC or hash when the key
contains sensitive identifiers such as email addresses or API tokens.
