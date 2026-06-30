# flowbrigade_redis

Redis storage adapter helpers for FlowBrigade rate limiting.

This package intentionally does not depend on a specific Redis client. Provide a
callback that runs `EVAL` and converts the returned Redis array into `seq[int64]`.

Client-specific bridge packages can build on this package. A bridge should
choose one supported OSS client, call that client correctly, and return
FlowBrigade's abstract storage surface.

```nim
import std/times
import pkg/flowbrigade/ratelimit
import pkg/flowbrigade_redis

let redisStorage = initRedisRateLimitStorage(
  proc(script: string; keys, args: seq[string]): seq[int64] =
    # Call your Redis client's EVAL command here.
    # Return the script result as five integers:
    # allowed, limit, remaining, retryAfterMs, resetAfterMs.
    discard
)
```

If your Redis client exposes a raw command API such as `execCommand("EVAL",
args)`, use `initRedisRateLimitStorageFromCommand`:

```nim
let redisStorage = initRedisRateLimitStorageFromCommand(
  proc(command: string; args: seq[string]): seq[int64] =
    # command == "EVAL"
    # args == @[script, keyCount, key1, ..., arg1, ...]
    #
    # Call your Redis client's raw command API here and convert the Redis array
    # response to seq[int64].
    discard
)
```

For clients that expose a raw command API, this wrapper maps naturally to an
`EVAL` command call. For clients that already expose an `eval` helper, use
`initRedisRateLimitStorage` directly.

```nim
let limiter = initStoredFixedWindow(
  prefix = "api",
  limit = 100,
  per = initDuration(minutes = 1),
  storage = redisStorage.asRateLimitStorage()
)

discard limiter.consume("user:42")
```

## Token bucket

Use `initRedisTokenBucket` when you need a shared token bucket instead of a
fixed window. The Redis Lua script uses Redis server time for refill
calculation, so multiple application processes can share the same limiter.

```nim
let bucket = initRedisTokenBucket(
  storage = redisStorage,
  key = "api:user:42",
  rate = 10,
  per = initDuration(seconds = 1),
  burst = 20
)

let decision = bucket.consume()
if not decision.allowed:
  echo "retry after: ", decision.retryAfter
```

Use `initRedisKeyedTokenBucket` when the bucket should be selected per request,
tenant, account, queue, or job class:

```nim
let bucket = initRedisKeyedTokenBucket(
  storage = redisStorage,
  namespace = "api",
  rate = 10,
  per = initDuration(seconds = 1),
  burst = 20
)

let decision = bucket.consume("user:42")
if not decision.allowed:
  echo "retry after: ", decision.retryAfter
```

Example shape for a raw command client:

```nim
proc toIntSeq(value: ClientRedisValue): seq[int64] =
  # Convert the Redis array returned by EVAL to seq[int64].
  # Keep this conversion close to the Redis client you use.
  discard

let redisStorage = initRedisRateLimitStorageFromCommand(
  proc(command: string; args: seq[string]): seq[int64] =
    toIntSeq(client.execCommand(command, args))
)
```

For the `ready` Redis client, use the official `flowbrigade_ready` bridge
package.

## Why Lua?

Redis executes Lua scripts atomically. The adapter uses that to keep the fixed
window update as one operation:

- read the current count
- decide whether the request is allowed
- increment the count when allowed
- set the key expiry
- return `RateLimitResult` metadata

Callers do not need to write Lua. The scripts are provided by this package.

## Tests

Run the unit tests with fake Redis:

```sh
nimble test
```

Run the real Redis integration test when `redis-cli` and Redis server are
available:

```sh
nimble integration
```

The integration test uses `FLOWBRIGADE_REDIS_HOST` and
`FLOWBRIGADE_REDIS_PORT`, defaulting to `127.0.0.1:6379`.
