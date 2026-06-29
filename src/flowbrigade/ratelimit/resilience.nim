import std/times

import ./errors
import ./result
import ./storage

type
  ## Chooses how a limiter behaves when external storage fails.
  StorageFailureMode* = enum
    failClosed, failOpen

proc fallbackResult(
    mode: StorageFailureMode;
    limit: int;
    per: Duration;
    cost: int
): RateLimitResult =
  case mode
  of failOpen:
    allowedResult(
      limit = limit,
      remaining = max(0, limit - cost),
      resetAfter = per
    )
  of failClosed:
    deniedResult(
      limit = limit,
      remaining = 0,
      retryAfter = per,
      resetAfter = per
    )

proc withStorageFailureMode*(
    storage: RateLimitStorage;
    mode: StorageFailureMode
): RateLimitStorage =
  ## Wraps storage callbacks with fail-open or fail-closed fallback behavior.
  ##
  ## This is useful for Redis or other remote stores where a network failure is
  ## operationally different from a real rate-limit denial.
  if storage.inspectFixedWindow.isNil:
    raise newException(RateLimitConfigError, "inspectFixedWindow proc must not be nil")
  if storage.consumeFixedWindow.isNil:
    raise newException(RateLimitConfigError, "consumeFixedWindow proc must not be nil")
  if storage.clearFixedWindow.isNil:
    raise newException(RateLimitConfigError, "clearFixedWindow proc must not be nil")

  RateLimitStorage(
    inspectFixedWindow: proc(
      key: string;
      limit: int;
      per: Duration;
      cost: int;
      current: Duration
    ): RateLimitResult =
      try:
        storage.inspectFixedWindow(key, limit, per, cost, current)
      except CatchableError:
        fallbackResult(mode, limit, per, cost),
    consumeFixedWindow: proc(
      key: string;
      limit: int;
      per: Duration;
      cost: int;
      current: Duration
    ): RateLimitResult =
      try:
        storage.consumeFixedWindow(key, limit, per, cost, current)
      except CatchableError:
        fallbackResult(mode, limit, per, cost),
    clearFixedWindow: proc(key: string): bool =
      try:
        storage.clearFixedWindow(key)
      except CatchableError:
        false
  )
