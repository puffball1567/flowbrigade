# Test matrix

This document tracks the behavior covered by the test suite. It is meant to
make gaps visible before adding new features.

## Duration parsing

| Area | Covered |
| --- | --- |
| zero values | `0s` |
| basic units | `ns`, `us`, `ms`, `s`, `m`, `h`, `d` |
| compound values | `1h30m`, `1h 30m 250ms` |
| spaces between values and units | `1 h 30 m` |
| repeated units | `1m60s` |
| decimals | `1.5s`, `1.5m`, `1.25ms` |
| surrounding whitespace | accepted |
| empty input | rejected |
| missing unit | rejected |
| missing value | rejected |
| unknown unit | rejected |
| calendar units | `mo`, `y` rejected |
| signs | leading `+` and `-` accepted |
| embedded signs | rejected |
| uppercase units | rejected |
| malformed decimals | rejected |
| trailing words | rejected |
| overflow | rejected as `DurationParseError` |
| oversized input | rejected by configurable length limit |

## Duration formatting

| Area | Covered |
| --- | --- |
| zero | `0s` |
| individual units | `ns`, `us`, `ms`, `s`, `m`, `h`, `d` |
| compound values | compact format without spaces |
| zero components | omitted |
| subsecond precision | `ms`, `us`, `ns` |
| negative durations | formatted with a leading `-` |

## Duration unit helpers

| Area | Covered |
| --- | --- |
| helpers | `ms`, `sec`, `min`, `hr`, `day` |
| negative values | accepted |

## Backoff

| Area | Covered |
| --- | --- |
| fixed policy | constant delay |
| linear policy | increment and cap behavior |
| exponential policy | factor and cap behavior |
| invalid attempts | attempt `0` rejected |
| invalid delays | zero and negative delays rejected |
| invalid policy shape | `maxDelay < initial` rejected |
| invalid factor | `factor <= 1` rejected |
| large attempts | capped without overflow |

## Jitter

| Area | Covered |
| --- | --- |
| no jitter | exact delay |
| full jitter | range from zero through base delay |
| equal jitter | range from half through base delay |
| decorrelated jitter | configured lower and upper bounds |

## Retry

| Area | Covered |
| --- | --- |
| eventual success | returns successful value |
| exhausted attempts | raises last operation exception |
| final failed attempt | does not sleep afterward |
| single attempt | no retry and no sleep |
| invalid max attempts | rejected |
| default sleep overload | covered |
| observer events | success, sleep, and exhausted paths covered |
| sleep failure | propagated |
| defects | not caught |

## Async retry

| Area | Covered |
| --- | --- |
| eventual success | returns successful value |
| exhausted attempts | raises last operation exception |
| invalid max attempts | rejected |
| default async sleep overload | covered |
| sleep failure | propagated |

## Fallback

| Area | Covered |
| --- | --- |
| Primary success | covered |
| Secondary after primary failure | covered |
| Async primary success | covered |
| Async secondary after primary future failure | covered |
| Provider metadata | covered |
| Async provider metadata | covered |
| All providers failed | typed `FallbackError` |
| Async all providers failed | typed `FallbackError` |
| Predicate stops fallback | covered |
| Async predicate stops fallback | covered |
| Observer events | covered |
| Async observer events | covered |
| Open circuit skips provider | covered |
| Async open circuit skips provider | covered |
| Circuit failure recording | covered |
| Async circuit failure recording | covered |
| Invalid fallback config | rejected |
| Invalid async fallback config | rejected |

## Rate limiting

| Area | Token bucket | Fixed window | Sliding window | Keyed fixed window |
| --- | --- | --- | --- | --- |
| normal allow/deny | covered | covered | covered | covered |
| refill/reset | covered | covered | covered | covered |
| boundary before reset | not applicable | covered | covered | covered through reset |
| custom cost | covered | covered | covered | covered |
| invalid config | covered | covered | covered | covered |
| invalid cost | covered | covered | covered | covered |
| cost above capacity | rejected | rejected | rejected | rejected |
| real time source constructor | covered | covered | covered | covered |
| manual time source constructor | covered | covered | covered | covered |
| result metadata | covered | covered | covered | covered |
| inspect without consume | covered | covered | covered | covered |
| retry/reset timing | covered | covered | covered | covered |
| explicit reset | covered | covered | covered | covered |
| configuration introspection | covered | covered | covered | covered |
| local state introspection | covered | covered | covered | covered |
| independent keys | not applicable | not applicable | not applicable | covered |
| non-string keys | not applicable | not applicable | not applicable | covered |
| unsafe string keys | not applicable | not applicable | not applicable | rejected |
| clear/reset one key | not applicable | not applicable | not applicable | covered |
| reset all keys | not applicable | not applicable | not applicable | covered |
| inspect does not retain new keys | not applicable | not applicable | not applicable | covered |
| max key capacity | not applicable | not applicable | not applicable | covered |
| expired key pruning | not applicable | not applicable | not applicable | covered |

## Compound rate limiting

| Area | Covered |
| --- | --- |
| all rules allowed | covered |
| any rule denied | covered |
| denied inspection prevents partial consumption | covered |
| inspect without consume | covered |
| mixed limiter types | covered |
| longest retry delay across denied rules | covered |
| invalid configuration | covered |

## Budget and quota

| Area | Covered |
| --- | --- |
| per-key usage accounting | covered |
| independent keys | covered |
| inspect without consume | covered |
| key trimming | covered |
| blank keys | rejected |
| non-positive cost | rejected |
| cost above budget | denied without mutating usage |
| period reset | covered |
| refund | covered and clamped at zero |
| key reset | covered |
| reset all | covered |
| config and presets | covered |
| invalid config | rejected |
| metric conversion | covered |

## Policy builders

| Area | Covered |
| --- | --- |
| API abuse protection bundle | covered |
| Login protection bundle | covered |
| Password reset protection bundle | covered |
| Third-party API client bundle | covered |
| Worker backpressure bundle | covered |
| Multi-tenant quota bundle | covered |
| Merge into caller registry | covered |
| Optional component initializers | covered |
| Validation report | covered |
| Required optional components | covered |
| Missing primary limiter | reported |
| Invalid optional policy values | reported |
| Invalid policy inputs | rejected |

## Control diagnostics

| Area | Covered |
| --- | --- |
| Empty signal window | covered |
| Insufficient sample window | covered |
| High failure rate hints | covered |
| Timeout pressure hints | covered |
| Rate-limit pressure hints | covered |
| Bulkhead saturation hints | covered |
| Healthy restore-normal hint | covered |
| Invalid diagnostics config | rejected |

## Observability export

| Area | Covered |
| --- | --- |
| Metric event to observation record | covered |
| Metric event to JSON | covered |
| Metric event to JSON line | covered through recipe |
| Metric event to Prometheus-style text | covered |
| Metric batch to JSON lines | covered |
| Observation batch to Prometheus-style text | covered |
| Empty observation batches | covered |
| Label escaping | covered |
| Metric and attribute name sanitization | covered |
| Empty metric/attribute names | rejected |
| Control report to JSON | covered |
| Control report to metric events | covered |

## Rate limit storage

| Area | Covered |
| --- | --- |
| shared stored state | covered |
| prefix namespace separation | covered |
| inspect without consume | covered |
| window reset | covered |
| result metadata | covered |
| invalid config | covered |
| invalid key/cost | covered |
| blank key | covered |
| oversized key | covered |
| control characters in key/prefix | rejected |
| clear key state | covered |
| key capacity | covered |
| expired key pruning | covered |
| invalid storage object | covered |
| real time source constructor | covered |

## Async rate limit storage

| Area | Covered |
| --- | --- |
| sync storage compatibility wrapper | covered |
| custom async callbacks | covered |
| shared stored state | covered |
| inspect without consume | covered |
| window reset | covered |
| result metadata | covered |
| clear key state | covered |
| audit events | covered |
| invalid config | covered |
| invalid key/cost | covered |

## Rate limit response helpers

| Area | Covered |
| --- | --- |
| standard headers | covered |
| legacy X-RateLimit headers | covered |
| Retry-After on denial | covered |
| text formatting | covered |
| framework-neutral HTTP decisions | covered |
| custom denied status/body | covered |
| standard-only/legacy-only/no-header modes | covered |
| typed denial exception | covered |
| remaining-or-raise helper | covered |
| sync wait helper | covered |
| async wait helper | covered |
| nil sleep proc | rejected |

## Rate limit key building

| Area | Covered |
| --- | --- |
| compound key building | covered |
| custom separator | covered |
| blank parts | rejected |
| control characters | rejected |
| separator in part | rejected |
| oversized part/key | rejected |
| opaque key with caller fingerprint | covered |
| unsafe fingerprint | rejected |

## Rate limit key extraction

| Area | Covered |
| --- | --- |
| compound extracted keys | covered |
| fluent part registration | covered |
| invalid extractor config | rejected |
| nil part proc | rejected |
| extractor without parts | rejected |
| unsafe extracted values | rejected |

## Rate string parsing

| Area | Covered |
| --- | --- |
| slash shorthand | `100/m` |
| dash shorthand | `5-S` |
| duration period | `1000/1h30m` |
| whitespace | trimmed |
| malformed strings | rejected |

## Adapter capabilities

| Area | Covered |
| --- | --- |
| custom capability set | covered |
| single capability requirement | covered |
| multiple capability requirement | covered |
| predefined in-memory capabilities | covered |
| predefined distributed fixed-window capabilities | covered |

## Limiter registry

| Area | Covered |
| --- | --- |
| named fixed window | covered |
| named keyed fixed window | covered |
| named token bucket | covered |
| named stored fixed window | covered |
| named compound limiter | covered |
| duplicate names | rejected |
| unknown names | rejected |
| custom limiter handles | covered |

## Rate-limit reservations

| Area | Covered |
| --- | --- |
| allowed decision | accepted immediately |
| denied within max wait | accepted |
| denied beyond max wait | rejected |
| sync wait | covered |
| async wait | covered |

## Storage resilience and audit

| Area | Covered |
| --- | --- |
| fail closed fallback | covered |
| fail open fallback | covered |
| clear failure fallback | covered |
| invalid wrapped storage | rejected |
| audit inspect event | covered |
| audit consume event | covered |
| audit clear event | covered |

## Bulkhead

| Area | Covered |
| --- | --- |
| acquire up to capacity | covered |
| deny above capacity | covered |
| release permits | covered |
| invalid capacity | rejected |
| release without permit | rejected |
| scoped helper releases after success | covered |
| scoped helper releases after failure | covered |
| scoped helper raises when full | covered |
| keyed independent capacity | covered |
| keyed release and clear | covered |
| keyed active entry count | covered |
| keyed scoped helper | covered |
| keyed non-string keys | covered |
| keyed blank key | rejected |
| keyed control-character key | rejected |
| keyed max key capacity | rejected |

## Lock store

| Area | Covered |
| --- | --- |
| acquire and release | covered |
| TTL expiry | covered |
| invalid keys | rejected |
| invalid TTL | rejected |
| invalid stores | rejected |
| refresh active lease | covered |
| refresh inactive lease | rejected |
| refresh expired lease | rejected |
| refresh stale lease | rejected |
| inspect active lease | covered |
| inspect expired lease | covered |
| inspect stale lease | covered |
| missing refresh/inspect adapter capabilities | rejected |
| scoped helper releases after success | covered |
| scoped helper releases after failure | covered |
| scoped helper raises when held | covered |

## Config objects and presets

| Area | Covered |
| --- | --- |
| retry config | covered |
| token bucket config | covered |
| fixed window config | covered |
| sliding window config | covered |
| keyed fixed window config | covered |
| circuit breaker config | covered |
| invalid config values | rejected |
| retry presets | covered |
| rate-limit presets | covered |
| circuit breaker preset | covered |

## Metric event conversion

| Area | Covered |
| --- | --- |
| retry event conversion | covered |
| circuit breaker event conversion | covered |
| stored limiter audit conversion | covered |
| clear audit conversion | covered |
| rate-limit decision conversion | covered |

## Redis adapter package

| Area | Covered |
| --- | --- |
| Redis eval callback integration | covered with fake Redis |
| fixed-window inspect without consume | covered |
| fixed-window clear key state | covered |
| fixed-window rollover | covered |
| fixed-window retry/reset metadata | covered |
| token-bucket allow/deny | covered |
| token-bucket inspect without consume | covered |
| token-bucket refill | covered |
| token-bucket clear key state | covered |
| real Redis fixed-window integration | covered |
| real Redis token-bucket integration | covered |
| invalid adapter config | covered |

## ready bridge package

| Area | Covered |
| --- | --- |
| nil connection | rejected |
| sync stored fixed-window integration | covered |
| sync token-bucket integration | covered |

## Memcached adapter package

| Area | Covered |
| --- | --- |
| Memcached callback integration | covered with fake Memcached |
| fixed-window allow/deny | covered |
| inspect without consume | covered |
| ttl-based rollover | covered |
| retry/reset metadata | covered |
| clear key state | covered |
| CAS conflict retry | covered |
| CAS retry exhaustion | covered |
| invalid adapter config | covered |
| malformed stored values | rejected |
| Memcached key length | rejected |
| real Memcached integration | covered when server is available |
| stale CAS token | rejected against real server |

## Prologue bridge package

| Area | Covered |
| --- | --- |
| allowed request continues to handler | covered with Prologue mocking |
| denied request returns 429 | covered with Prologue mocking |
| rate-limit headers | covered |
| header-based key extraction | covered |
| query parameter key extraction | covered |
| path parameter and cookie key extraction | covered |
| compound key extraction | covered |
| named limiter registry middleware | covered |
| method-scoped middleware | covered |
| custom denied content type | covered |
| disabled rate-limit headers | covered |
| thread-safe policy middleware overload | covered |
| config file API abuse middleware | covered |
| config file login middleware | covered |
| login guard middleware | covered with account and identity key composition |
| password reset guard middleware | covered |
| deadline middleware | covered before and after expiry |
| invalid bridge configuration | rejected |

## Internal time source

| Area | Covered |
| --- | --- |
| manual default start | zero |
| manual custom start | covered |
| deterministic advance | covered |
| negative advance | rejected as `TimeSourceError` |
| monotonic source | does not move backwards |

## Throttle

| Area | Covered |
| --- | --- |
| first action | allowed immediately |
| repeated action before interval | blocked |
| interval boundary | allowed |
| reset | covered |
| invalid interval | rejected |
| real time source constructor | covered |

## Debounce

| Area | Covered |
| --- | --- |
| no pending call | not ready |
| latest call wins | covered |
| ready after delay | covered |
| consume once | covered |
| cancel | covered |
| invalid delay | rejected |
| real time source constructor | covered |

## Circuit breaker

| Area | Covered |
| --- | --- |
| initial state | closed |
| failure threshold | opens |
| open state | blocks calls |
| reset delay | moves to half open |
| half-open success | closes |
| half-open failure | reopens |
| invalid configuration | rejected |
| real time source constructor | covered |
| observer events | covered |

## Timeout

| Area | Covered |
| --- | --- |
| before deadline | not expired |
| at deadline | expired |
| elapsed time | covered |
| remaining time | capped at zero |
| zero duration | expired immediately |
| negative duration | rejected |
| real time source constructor | covered |

## Deadline

| Area | Covered |
| --- | --- |
| relative deadline before expiry | not expired |
| relative deadline at boundary | expired |
| remaining time | capped at zero |
| zero duration | expired immediately |
| negative relative deadline | rejected |
| absolute future deadline | covered |
| absolute current-time deadline | expired |
| absolute past deadline | expired |
| negative absolute deadline | rejected |
| real time source constructors | covered |
| clamp requested duration | covered |
| clamp zero duration | covered |
| negative clamp request | rejected |
| child deadline shorter than parent | covered |
| child deadline capped by parent | covered |
| child deadline expiry time | covered |
| child deadline zero duration | expired immediately |
| child deadline from expired parent | expired |
| conversion to timeout | covered |
| conversion from expired deadline | expired immediately |

## C ABI

| Area | Covered |
| --- | --- |
| duration parse | returns nanoseconds and error codes |
| duration format | writes caller-owned buffers and reports required length |
| backoff handles | fixed, linear, and exponential delay calculation |
| token bucket handle | create, consume, denial metadata, destroy |
| fixed window handle | create, inspect, consume, denial, destroy |
| sliding window handle | create, consume, denial, destroy |
| circuit breaker handle | create, allow, record failure, state, destroy |
| bulkhead handle | create, inspect, acquire, release, destroy |
| timeout and deadline handles | create, expired, elapsed/remaining, clamp, destroy |
| budget ledger handle | create, inspect, consume, denial, refund, reset, reset all, destroy |
| lock store handle | create, acquire, conflict, inspect, refresh, release, release key, destroy |
| throttle and debounce handles | create, allow/ready, reset/cancel, destroy |
| retry callback ABI | success after retries, exhausted attempts, sleep callback failure, invalid input |
| fallback callback ABI | ordered success, exhausted providers, predicate stop, circuit breaker skip/record, invalid input |
| limiter registry ABI | fixed, keyed, token bucket, compound, stored fixed window callbacks, inspect/consume/allow/clear, invalid input |
| C callback storage ABI | inspect, consume, clear, callback failure, nil callback rejection |
| metrics export ABI | rate-limit and budget results to JSON lines and Prometheus-style text, buffer sizing, invalid input |
| ABI metadata | `fb_abi_version`, `fb_abi_version_string`, `fb_abi_supports`, and `fb_last_error` |
| invalid arguments | converted to `FB_ERR_INVALID_ARGUMENT` |
| C link smoke test | builds and runs against `include/flowbrigade.h` |

## Known gaps

- `retry` currently requires an explicit sleep proc.
- Duration parser rounding for values below one nanosecond is not specified.
- Duration overflow around compound decimal values could use more targeted tests.
- Jitter tests check ranges, not deterministic seeded values.
- Async retry does not include a default async sleep helper yet.
- Timeout and deadline helpers only track time; they do not cancel running work.
- Benchmarks are documented but not implemented yet.
