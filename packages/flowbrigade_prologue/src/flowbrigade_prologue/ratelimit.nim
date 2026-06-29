import std/[httpcore, strutils]

import flowbrigade
import prologue

import ./keys

proc applyHeaders(ctx: Context; headers: openArray[RateLimitHeader]) =
  for header in headers:
    ctx.response.setHeader(header.name, header.value)

proc methodAllowed(httpMethod: HttpMethod; allowedMethods: set[HttpMethod]): bool =
  allowedMethods.len == 0 or httpMethod in allowedMethods

proc applyRateLimitDecision(
    ctx: Context;
    decision: RateLimitResult;
    deniedStatusCode: int;
    deniedBody, contentType: string;
    headerMode: RateLimitHeaderMode
): bool =
  let http = httpLimitDecision(
    decision,
    deniedStatusCode = deniedStatusCode,
    deniedBody = deniedBody,
    headerMode = headerMode
  )
  ctx.applyHeaders(http.headers)
  if http.allowed:
    return true
  ctx.response.code = HttpCode(http.statusCode)
  ctx.response.body = http.body
  if contentType.len > 0:
    ctx.response.setHeader("Content-Type", contentType)
  false

proc consumePolicy(policy: FlowPolicy; key: string; cost: int): RateLimitResult {.gcsafe.} =
  {.cast(gcsafe).}:
    result = policy.consume(key, cost)

proc consumePolicy(
    policy: ThreadSafeFlowPolicy;
    key: string;
    cost: int
): RateLimitResult {.gcsafe.} =
  {.cast(gcsafe).}:
    result = policy.consume(key, cost)

proc consumeRegistry(
    registry: LimiterRegistry;
    name, key: string;
    cost: int
): RateLimitResult {.gcsafe.} =
  {.cast(gcsafe).}:
    result = registry.consume(name, key, cost)

proc consumeRegistry(
    registry: ThreadSafeLimiterRegistry;
    name, key: string;
    cost: int
): RateLimitResult {.gcsafe.} =
  {.cast(gcsafe).}:
    result = registry.consume(name, key, cost)

proc rateLimitMiddleware*(
    policy: FlowPolicy;
    key: PrologueRateLimitKeyProc;
    cost = 1;
    deniedStatusCode = 429;
    deniedBody = "Too many requests";
    headerMode = standardAndLegacyRateLimitHeaders;
    allowedMethods: set[HttpMethod] = {};
    contentType = "text/plain; charset=UTF-8"
): HandlerAsync =
  ## Converts a FlowBrigade policy into Prologue middleware.
  ##
  ## On allow, rate-limit headers are attached and the request continues to the
  ## next middleware/handler. On deny, the middleware writes the response and
  ## does not call `switch(ctx)`.
  key.requireKeyProc()
  result = proc(ctx: Context) {.async, gcsafe.} =
    if not ctx.request.reqMethod.methodAllowed(allowedMethods):
      await switch(ctx)
      return
    let decision = consumePolicy(policy, key(ctx), cost)
    if ctx.applyRateLimitDecision(
      decision, deniedStatusCode, deniedBody, contentType, headerMode
    ):
      await switch(ctx)

proc rateLimitMiddleware*(
    policy: ThreadSafeFlowPolicy;
    key: PrologueRateLimitKeyProc;
    cost = 1;
    deniedStatusCode = 429;
    deniedBody = "Too many requests";
    headerMode = standardAndLegacyRateLimitHeaders;
    allowedMethods: set[HttpMethod] = {};
    contentType = "text/plain; charset=UTF-8"
): HandlerAsync =
  ## Converts a thread-safe FlowBrigade policy into Prologue middleware.
  key.requireKeyProc()
  result = proc(ctx: Context) {.async, gcsafe.} =
    if not ctx.request.reqMethod.methodAllowed(allowedMethods):
      await switch(ctx)
      return
    let decision = consumePolicy(policy, key(ctx), cost)
    if ctx.applyRateLimitDecision(
      decision, deniedStatusCode, deniedBody, contentType, headerMode
    ):
      await switch(ctx)

proc rateLimitMiddleware*(
    registry: LimiterRegistry;
    limiterName: string;
    key: PrologueRateLimitKeyProc;
    cost = 1;
    deniedStatusCode = 429;
    deniedBody = "Too many requests";
    headerMode = standardAndLegacyRateLimitHeaders;
    allowedMethods: set[HttpMethod] = {};
    contentType = "text/plain; charset=UTF-8"
): HandlerAsync =
  ## Converts a named FlowBrigade limiter into Prologue middleware.
  key.requireKeyProc()
  let name = limiterName.strip()
  if name.len == 0:
    raise newException(PrologueBridgeConfigError, "limiter name must not be empty")
  result = proc(ctx: Context) {.async, gcsafe.} =
    if not ctx.request.reqMethod.methodAllowed(allowedMethods):
      await switch(ctx)
      return
    let decision = consumeRegistry(registry, name, key(ctx), cost)
    if ctx.applyRateLimitDecision(
      decision, deniedStatusCode, deniedBody, contentType, headerMode
    ):
      await switch(ctx)

proc rateLimitMiddleware*(
    registry: ThreadSafeLimiterRegistry;
    limiterName: string;
    key: PrologueRateLimitKeyProc;
    cost = 1;
    deniedStatusCode = 429;
    deniedBody = "Too many requests";
    headerMode = standardAndLegacyRateLimitHeaders;
    allowedMethods: set[HttpMethod] = {};
    contentType = "text/plain; charset=UTF-8"
): HandlerAsync =
  ## Converts a named thread-safe FlowBrigade limiter into Prologue middleware.
  key.requireKeyProc()
  let name = limiterName.strip()
  if name.len == 0:
    raise newException(PrologueBridgeConfigError, "limiter name must not be empty")
  result = proc(ctx: Context) {.async, gcsafe.} =
    if not ctx.request.reqMethod.methodAllowed(allowedMethods):
      await switch(ctx)
      return
    let decision = consumeRegistry(registry, name, key(ctx), cost)
    if ctx.applyRateLimitDecision(
      decision, deniedStatusCode, deniedBody, contentType, headerMode
    ):
      await switch(ctx)
