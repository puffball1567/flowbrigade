# flowbrigade_ready

Bridge package for using the `ready` OSS Redis client with FlowBrigade.

Supported provider:

- `ready >= 0.1.9`

`ready` was selected because it exposes raw Redis commands and compiles on Nim
2.2.

Supported FlowBrigade surfaces:

- sync `RateLimitStorage` for stored fixed-window rate limiting
- sync Redis token bucket through `flowbrigade_redis`

```nim
import std/times
import ready
import pkg/flowbrigade/ratelimit
import pkg/flowbrigade_ready

let conn = newRedisConn("127.0.0.1", Port(6379))
let redisStorage = initReadyRateLimitStorage(conn)

let limiter = initStoredFixedWindow(
  prefix = "api",
  limit = 100,
  per = initDuration(minutes = 1),
  storage = redisStorage.asRateLimitStorage()
)

discard limiter.consume("user:42")
```

## Responsibility

This package owns the mapping from `ready.RedisReply` to FlowBrigade's abstract
storage types. It does not own Redis server configuration or connection pooling.
