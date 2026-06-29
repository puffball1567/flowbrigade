import std/strutils

import flowbrigade
import prologue

import ./keys
import ./ratelimit

proc requireKeyPrefix(prefix: string): string =
  result = prefix.strip()
  if result.len == 0:
    raise newException(PrologueBridgeConfigError, "key prefix must not be empty")

proc authAttemptKey*(
    prefix: string;
    accountKey, identityKey: PrologueRateLimitKeyProc
): PrologueRateLimitKeyProc =
  ## Builds a stable key for authentication-style guards.
  ##
  ## The account part should identify the protected account or tenant. The
  ## identity part should identify the caller, such as an IP address or trusted
  ## session/user-agent fingerprint.
  let keyPrefix = requireKeyPrefix(prefix)
  accountKey.requireKeyProc()
  identityKey.requireKeyProc()
  result = proc(ctx: Context): string {.gcsafe.} =
    rateLimitKey([keyPrefix, accountKey(ctx), identityKey(ctx)])

proc loginGuardMiddleware*(
    policy: FlowPolicy;
    accountKey, identityKey: PrologueRateLimitKeyProc;
    cost = 1;
    deniedStatusCode = 429;
    deniedBody = "Too many login attempts";
    headerMode = standardAndLegacyRateLimitHeaders
): HandlerAsync =
  ## Prologue middleware for `loginProtectionPolicy`.
  rateLimitMiddleware(
    policy,
    authAttemptKey("login", accountKey, identityKey),
    cost = cost,
    deniedStatusCode = deniedStatusCode,
    deniedBody = deniedBody,
    headerMode = headerMode
  )

proc loginGuardMiddleware*(
    policy: ThreadSafeFlowPolicy;
    accountKey, identityKey: PrologueRateLimitKeyProc;
    cost = 1;
    deniedStatusCode = 429;
    deniedBody = "Too many login attempts";
    headerMode = standardAndLegacyRateLimitHeaders
): HandlerAsync =
  ## Prologue middleware for a thread-safe `loginProtectionPolicy`.
  rateLimitMiddleware(
    policy,
    authAttemptKey("login", accountKey, identityKey),
    cost = cost,
    deniedStatusCode = deniedStatusCode,
    deniedBody = deniedBody,
    headerMode = headerMode
  )

proc passwordResetGuardMiddleware*(
    policy: FlowPolicy;
    accountKey, identityKey: PrologueRateLimitKeyProc;
    cost = 1;
    deniedStatusCode = 429;
    deniedBody = "Too many password reset attempts";
    headerMode = standardAndLegacyRateLimitHeaders
): HandlerAsync =
  ## Prologue middleware for `passwordResetProtectionPolicy`.
  rateLimitMiddleware(
    policy,
    authAttemptKey("password_reset", accountKey, identityKey),
    cost = cost,
    deniedStatusCode = deniedStatusCode,
    deniedBody = deniedBody,
    headerMode = headerMode
  )

proc passwordResetGuardMiddleware*(
    policy: ThreadSafeFlowPolicy;
    accountKey, identityKey: PrologueRateLimitKeyProc;
    cost = 1;
    deniedStatusCode = 429;
    deniedBody = "Too many password reset attempts";
    headerMode = standardAndLegacyRateLimitHeaders
): HandlerAsync =
  ## Prologue middleware for a thread-safe `passwordResetProtectionPolicy`.
  rateLimitMiddleware(
    policy,
    authAttemptKey("password_reset", accountKey, identityKey),
    cost = cost,
    deniedStatusCode = deniedStatusCode,
    deniedBody = deniedBody,
    headerMode = headerMode
  )
