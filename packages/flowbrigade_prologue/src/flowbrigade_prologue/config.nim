import std/[httpcore, parsecfg, strutils, times]

import flowbrigade
import prologue

import ./auth_guards
import ./keys
import ./ratelimit

type
  PrologueConfigError* = object of PrologueBridgeConfigError

  ProloguePolicyKind* = enum
    ppkApiAbuse,
    ppkLogin,
    ppkPasswordReset

  PrologueStateBackend* = enum
    psbMemory,
    psbThreadSafeMemory

  PrologueKeyKind* = enum
    pkkPath,
    pkkMethodPath,
    pkkHeader,
    pkkForwardedFor,
    pkkQuery,
    pkkPost,
    pkkForm,
    pkkPathParam,
    pkkCookie

  PrologueKeyConfig* = object
    kind*: PrologueKeyKind
    name*: string
    fallback*: string

  PrologueRateLimitConfig* = object
    policy*: ProloguePolicyKind
    backend*: PrologueStateBackend
    key*: PrologueKeyConfig
    accountKey*: PrologueKeyConfig
    identityKey*: PrologueKeyConfig
    allowedMethods*: set[HttpMethod]
    cost*: int
    deniedStatusCode*: int
    deniedBody*: string
    contentType*: string
    headerMode*: RateLimitHeaderMode
    name*: string
    perIdentityLimit*: int
    perIdentityWindow*: Duration
    globalRate*: int
    globalPer*: Duration
    globalBurst*: int
    accountLimit*: int
    accountWindow*: Duration
    identityLimit*: int
    identityWindow*: Duration

proc configError(message: string): ref PrologueConfigError =
  newException(PrologueConfigError, message)

proc requireValue(values: Config; section, key: string): string =
  result = values.getSectionValue(section, key).strip()
  if result.len == 0:
    raise configError("missing required config value: " & section & "." & key)

proc optionalValue(values: Config; section, key, default: string): string =
  result = values.getSectionValue(section, key, default).strip()

proc parsePositiveInt(name, value: string): int =
  try:
    result = parseInt(value)
  except ValueError:
    raise configError(name & " must be an integer")
  if result <= 0:
    raise configError(name & " must be positive")

proc parsePolicyKind(value: string): ProloguePolicyKind =
  case value.normalize()
  of "apiabuse", "apiabuseprotection", "api":
    ppkApiAbuse
  of "login", "loginprotection":
    ppkLogin
  of "passwordreset", "passwordresetprotection":
    ppkPasswordReset
  else:
    raise configError("policy must be api_abuse, login, or password_reset")

proc parseBackend(value: string): PrologueStateBackend =
  case value.normalize()
  of "memory", "inmemory":
    psbMemory
  of "threadsafememory", "threadsafe", "threadsafeinmemory":
    psbThreadSafeMemory
  else:
    raise configError("backend must be memory or thread_safe_memory")

proc parseHeaderMode(value: string): RateLimitHeaderMode =
  case value.normalize()
  of "standardandlegacy", "both", "all":
    standardAndLegacyRateLimitHeaders
  of "standard":
    standardRateLimitHeaders
  of "legacy", "xratelimit":
    legacyRateLimitHeaders
  of "none", "off", "disabled":
    noRateLimitHeaders
  else:
    raise configError("header_mode must be standard_and_legacy, standard, legacy, or none")

proc parseHttpMethod(value: string): HttpMethod =
  case value.normalize()
  of "get": HttpGet
  of "post": HttpPost
  of "put": HttpPut
  of "delete": HttpDelete
  of "patch": HttpPatch
  of "head": HttpHead
  of "options": HttpOptions
  else:
    raise configError("unsupported HTTP method: " & value)

proc parseAllowedMethods(value: string): set[HttpMethod] =
  result = {}
  let input = value.strip()
  if input.len == 0:
    return
  for item in input.split(","):
    let httpMethod = item.strip()
    if httpMethod.len > 0:
      result.incl(parseHttpMethod(httpMethod))

proc parseKeyKind(value: string): PrologueKeyKind =
  case value.normalize()
  of "path": pkkPath
  of "methodpath", "method_path": pkkMethodPath
  of "header": pkkHeader
  of "forwardedfor", "forwarded_for": pkkForwardedFor
  of "query", "queryparam", "query_param": pkkQuery
  of "post", "postparam", "post_param": pkkPost
  of "form", "formparam", "form_param": pkkForm
  of "pathparam", "path_param": pkkPathParam
  of "cookie": pkkCookie
  else:
    raise configError("unsupported key kind: " & value)

proc initKeyConfig*(
    kind: PrologueKeyKind;
    name = "";
    fallback = "unknown"
): PrologueKeyConfig =
  PrologueKeyConfig(kind: kind, name: name.strip(), fallback: fallback)

proc parseKeySpec(value: string): PrologueKeyConfig =
  let input = value.strip()
  if input.len == 0:
    raise configError("key spec must not be empty")
  let parts = input.split(":", maxsplit = 1)
  let kind = parseKeyKind(parts[0])
  let name = if parts.len == 2: parts[1].strip() else: ""
  initKeyConfig(kind = kind, name = name)

proc validateKeyConfig(config: PrologueKeyConfig; source: string) =
  case config.kind
  of pkkHeader, pkkQuery, pkkPost, pkkForm, pkkPathParam, pkkCookie:
    if config.name.len == 0:
      raise configError("key spec requires a name: " & source)
  else:
    discard

proc parseKeyConfig(
    values: Config;
    section, optionPrefix, defaultSpec: string
): PrologueKeyConfig =
  let spec = values.optionalValue(section, optionPrefix, defaultSpec)
  result = parseKeySpec(spec)
  let name = values.optionalValue(section, optionPrefix & "_name", "")
  if name.len > 0:
    result.name = name
  let fallback = values.optionalValue(section, optionPrefix & "_fallback", "")
  if fallback.len > 0:
    result.fallback = fallback
  validateKeyConfig(result, optionPrefix)

proc keyProc*(config: PrologueKeyConfig): PrologueRateLimitKeyProc =
  case config.kind
  of pkkPath:
    pathKey()
  of pkkMethodPath:
    methodPathKey()
  of pkkHeader:
    headerKey(config.name, fallback = config.fallback)
  of pkkForwardedFor:
    forwardedForKey(fallback = config.fallback)
  of pkkQuery:
    queryParamKey(config.name, fallback = config.fallback)
  of pkkPost:
    postParamKey(config.name, fallback = config.fallback)
  of pkkForm:
    formParamKey(config.name, fallback = config.fallback)
  of pkkPathParam:
    pathParamKey(config.name, fallback = config.fallback)
  of pkkCookie:
    cookieKey(config.name, fallback = config.fallback)

proc defaultPrologueRateLimitConfig*(): PrologueRateLimitConfig =
  PrologueRateLimitConfig(
    policy: ppkApiAbuse,
    backend: psbMemory,
    key: initKeyConfig(pkkPath),
    accountKey: initKeyConfig(pkkHeader, "X-Account-ID"),
    identityKey: initKeyConfig(pkkForwardedFor),
    allowedMethods: {},
    cost: 1,
    deniedStatusCode: 429,
    deniedBody: "Too many requests",
    contentType: "text/plain; charset=UTF-8",
    headerMode: standardAndLegacyRateLimitHeaders,
    name: "",
    perIdentityLimit: 120,
    perIdentityWindow: 1.min,
    globalRate: 1000,
    globalPer: 1.sec,
    globalBurst: 2000,
    accountLimit: 5,
    accountWindow: 15.min,
    identityLimit: 20,
    identityWindow: 1.hr
  )

proc prologueRateLimitConfigFromFile*(
    path: string;
    section = "rate_limit"
): PrologueRateLimitConfig =
  let values =
    try:
      loadConfig(path)
    except CatchableError as e:
      raise configError("could not load config file: " & e.msg)
  result = defaultPrologueRateLimitConfig()
  result.policy = parsePolicyKind(values.requireValue(section, "policy"))
  result.backend = parseBackend(values.optionalValue(section, "backend", "memory"))
  result.key = parseKeyConfig(values, section, "key", "path")
  result.accountKey = parseKeyConfig(values, section, "account_key", "header:X-Account-ID")
  result.identityKey = parseKeyConfig(values, section, "identity_key", "forwarded_for")
  result.allowedMethods = parseAllowedMethods(values.optionalValue(section, "allowed_methods", ""))
  result.cost = parsePositiveInt("cost", values.optionalValue(section, "cost", "1"))
  result.deniedStatusCode = parsePositiveInt(
    "denied_status_code",
    values.optionalValue(section, "denied_status_code", "429")
  )
  result.deniedBody = values.optionalValue(section, "denied_body", result.deniedBody)
  result.contentType = values.optionalValue(section, "content_type", result.contentType)
  result.headerMode = parseHeaderMode(values.optionalValue(section, "header_mode", "standard_and_legacy"))
  result.name = values.optionalValue(section, "name", "")

  case result.policy
  of ppkApiAbuse:
    result.perIdentityLimit = parsePositiveInt(
      "per_identity_limit",
      values.optionalValue(section, "per_identity_limit", $result.perIdentityLimit)
    )
    result.perIdentityWindow = parseDuration(
      values.optionalValue(section, "per_identity_window", "1m")
    )
    result.globalRate = parsePositiveInt("global_rate", values.optionalValue(section, "global_rate", $result.globalRate))
    result.globalPer = parseDuration(values.optionalValue(section, "global_per", "1s"))
    result.globalBurst = parsePositiveInt("global_burst", values.optionalValue(section, "global_burst", $result.globalBurst))
  of ppkLogin, ppkPasswordReset:
    let defaultAccountLimit = if result.policy == ppkLogin: 5 else: 3
    let defaultAccountWindow = if result.policy == ppkLogin: "15m" else: "1h"
    let defaultIdentityLimit = if result.policy == ppkLogin: 20 else: 10
    result.accountLimit = parsePositiveInt(
      "account_limit",
      values.optionalValue(section, "account_limit", $defaultAccountLimit)
    )
    result.accountWindow = parseDuration(values.optionalValue(section, "account_window", defaultAccountWindow))
    result.identityLimit = parsePositiveInt(
      "identity_limit",
      values.optionalValue(section, "identity_limit", $defaultIdentityLimit)
    )
    result.identityWindow = parseDuration(values.optionalValue(section, "identity_window", "1h"))

proc buildPolicy(config: PrologueRateLimitConfig): FlowPolicy =
  let policyName = config.name.strip()
  case config.policy
  of ppkApiAbuse:
    if policyName.len == 0:
      apiAbuseProtectionPolicy(
        perIdentityLimit = config.perIdentityLimit,
        perIdentityWindow = config.perIdentityWindow,
        globalRate = config.globalRate,
        globalPer = config.globalPer,
        globalBurst = config.globalBurst
      )
    else:
      apiAbuseProtectionPolicy(
        name = policyName,
        perIdentityLimit = config.perIdentityLimit,
        perIdentityWindow = config.perIdentityWindow,
        globalRate = config.globalRate,
        globalPer = config.globalPer,
        globalBurst = config.globalBurst
      )
  of ppkLogin:
    if policyName.len == 0:
      loginProtectionPolicy(
        accountLimit = config.accountLimit,
        accountWindow = config.accountWindow,
        identityLimit = config.identityLimit,
        identityWindow = config.identityWindow
      )
    else:
      loginProtectionPolicy(
        name = policyName,
        accountLimit = config.accountLimit,
        accountWindow = config.accountWindow,
        identityLimit = config.identityLimit,
        identityWindow = config.identityWindow
      )
  of ppkPasswordReset:
    if policyName.len == 0:
      passwordResetProtectionPolicy(
        accountLimit = config.accountLimit,
        accountWindow = config.accountWindow,
        identityLimit = config.identityLimit,
        identityWindow = config.identityWindow
      )
    else:
      passwordResetProtectionPolicy(
        name = policyName,
        accountLimit = config.accountLimit,
        accountWindow = config.accountWindow,
        identityLimit = config.identityLimit,
        identityWindow = config.identityWindow
      )

proc prologueRateLimitMiddleware*(config: PrologueRateLimitConfig): HandlerAsync =
  let policy = buildPolicy(config)
  case config.policy
  of ppkApiAbuse:
    case config.backend
    of psbMemory:
      rateLimitMiddleware(
        policy,
        config.key.keyProc(),
        cost = config.cost,
        deniedStatusCode = config.deniedStatusCode,
        deniedBody = config.deniedBody,
        headerMode = config.headerMode,
        allowedMethods = config.allowedMethods,
        contentType = config.contentType
      )
    of psbThreadSafeMemory:
      rateLimitMiddleware(
        initThreadSafeFlowPolicy(policy),
        config.key.keyProc(),
        cost = config.cost,
        deniedStatusCode = config.deniedStatusCode,
        deniedBody = config.deniedBody,
        headerMode = config.headerMode,
        allowedMethods = config.allowedMethods,
        contentType = config.contentType
      )
  of ppkLogin:
    case config.backend
    of psbMemory:
      loginGuardMiddleware(
        policy,
        accountKey = config.accountKey.keyProc(),
        identityKey = config.identityKey.keyProc(),
        cost = config.cost,
        deniedStatusCode = config.deniedStatusCode,
        deniedBody = config.deniedBody,
        headerMode = config.headerMode
      )
    of psbThreadSafeMemory:
      loginGuardMiddleware(
        initThreadSafeFlowPolicy(policy),
        accountKey = config.accountKey.keyProc(),
        identityKey = config.identityKey.keyProc(),
        cost = config.cost,
        deniedStatusCode = config.deniedStatusCode,
        deniedBody = config.deniedBody,
        headerMode = config.headerMode
      )
  of ppkPasswordReset:
    case config.backend
    of psbMemory:
      passwordResetGuardMiddleware(
        policy,
        accountKey = config.accountKey.keyProc(),
        identityKey = config.identityKey.keyProc(),
        cost = config.cost,
        deniedStatusCode = config.deniedStatusCode,
        deniedBody = config.deniedBody,
        headerMode = config.headerMode
      )
    of psbThreadSafeMemory:
      passwordResetGuardMiddleware(
        initThreadSafeFlowPolicy(policy),
        accountKey = config.accountKey.keyProc(),
        identityKey = config.identityKey.keyProc(),
        cost = config.cost,
        deniedStatusCode = config.deniedStatusCode,
        deniedBody = config.deniedBody,
        headerMode = config.headerMode
      )

proc prologueRateLimitMiddlewareFromFile*(
    path: string;
    section = "rate_limit"
): HandlerAsync =
  prologueRateLimitMiddleware(prologueRateLimitConfigFromFile(path, section))
