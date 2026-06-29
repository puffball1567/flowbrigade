import std/[options, strutils]

import flowbrigade
import prologue

type
  PrologueBridgeConfigError* = object of ValueError

  PrologueRateLimitKeyProc* = proc(ctx: Context): string {.closure, gcsafe.}

proc requireHeaderName*(name: string): string =
  result = name.strip()
  if result.len == 0:
    raise newException(PrologueBridgeConfigError, "header name must not be empty")

proc requireKeyProc*(key: PrologueRateLimitKeyProc) =
  if key.isNil:
    raise newException(PrologueBridgeConfigError, "rate-limit key proc must not be nil")

proc requireParamName*(name: string): string =
  result = name.strip()
  if result.len == 0:
    raise newException(PrologueBridgeConfigError, "parameter name must not be empty")

proc fallbackOrValue(value, fallback: string): string =
  let trimmed = value.strip()
  if trimmed.len == 0: fallback else: trimmed

proc firstHeaderValue*(ctx: Context; name: string): string =
  ## Returns the first request header value for `name`, or an empty string.
  let headerName = requireHeaderName(name)
  if not ctx.request.hasHeader(headerName):
    return ""
  let values = ctx.request.getHeader(headerName)
  if values.len == 0:
    return ""
  values[0].strip()

proc headerKey*(name: string; fallback = "unknown"): PrologueRateLimitKeyProc =
  ## Builds a key extractor from a request header.
  let headerName = requireHeaderName(name)
  result = proc(ctx: Context): string {.gcsafe.} =
    fallbackOrValue(ctx.firstHeaderValue(headerName), fallback)

proc forwardedForKey*(
    forwardedHeader = "X-Forwarded-For";
    realIpHeader = "X-Real-IP";
    fallback = "unknown"
): PrologueRateLimitKeyProc =
  ## Uses common reverse-proxy IP headers.
  ##
  ## Applications should only trust these headers when a trusted reverse proxy
  ## sets or sanitizes them.
  let forwarded = requireHeaderName(forwardedHeader)
  let realIp = requireHeaderName(realIpHeader)
  result = proc(ctx: Context): string {.gcsafe.} =
    let forwardedValue = ctx.firstHeaderValue(forwarded)
    if forwardedValue.len > 0:
      return forwardedValue.split(",")[0].strip()
    let realIpValue = ctx.firstHeaderValue(realIp)
    if realIpValue.len > 0: realIpValue else: fallback

proc pathKey*(): PrologueRateLimitKeyProc =
  ## Builds a key from the request path.
  result = proc(ctx: Context): string {.gcsafe.} =
    ctx.request.path

proc methodPathKey*(): PrologueRateLimitKeyProc =
  ## Builds a key from the HTTP method and request path.
  result = proc(ctx: Context): string {.gcsafe.} =
    $ctx.request.reqMethod & ":" & ctx.request.path

proc queryParamKey*(name: string; fallback = "unknown"): PrologueRateLimitKeyProc =
  ## Builds a key from a query parameter.
  let paramName = requireParamName(name)
  result = proc(ctx: Context): string {.gcsafe.} =
    let value = ctx.getQueryParamsOption(paramName)
    if value.isSome: fallbackOrValue(value.get(), fallback) else: fallback

proc postParamKey*(name: string; fallback = "unknown"): PrologueRateLimitKeyProc =
  ## Builds a key from a form-urlencoded POST parameter.
  let paramName = requireParamName(name)
  result = proc(ctx: Context): string {.gcsafe.} =
    let value = ctx.getPostParamsOption(paramName)
    if value.isSome: fallbackOrValue(value.get(), fallback) else: fallback

proc formParamKey*(name: string; fallback = "unknown"): PrologueRateLimitKeyProc =
  ## Builds a key from a parsed form parameter.
  let paramName = requireParamName(name)
  result = proc(ctx: Context): string {.gcsafe.} =
    let value = ctx.getFormParamsOption(paramName)
    if value.isSome: fallbackOrValue(value.get(), fallback) else: fallback

proc pathParamKey*(name: string; fallback = "unknown"): PrologueRateLimitKeyProc =
  ## Builds a key from a route path parameter.
  let paramName = requireParamName(name)
  result = proc(ctx: Context): string {.gcsafe.} =
    let value = ctx.getPathParamsOption(paramName)
    if value.isSome: fallbackOrValue(value.get(), fallback) else: fallback

proc cookieKey*(name: string; fallback = "unknown"): PrologueRateLimitKeyProc =
  ## Builds a key from a request cookie.
  let cookieName = requireParamName(name)
  result = proc(ctx: Context): string {.gcsafe.} =
    fallbackOrValue(ctx.getCookie(cookieName, fallback), fallback)

proc compoundKey*(
    prefix: string;
    parts: openArray[PrologueRateLimitKeyProc]
): PrologueRateLimitKeyProc =
  ## Builds one validated FlowBrigade key from multiple Prologue key extractors.
  let keyPrefix = requireParamName(prefix)
  if parts.len == 0:
    raise newException(PrologueBridgeConfigError, "compound key requires at least one part")
  var checkedParts: seq[PrologueRateLimitKeyProc] = @[]
  for part in parts:
    part.requireKeyProc()
    checkedParts.add(part)
  result = proc(ctx: Context): string {.gcsafe.} =
    var values = @[keyPrefix]
    for part in checkedParts:
      values.add(part(ctx))
    rateLimitKey(values)
