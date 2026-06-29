# Security Policy

## Supported Versions

Security fixes are provided for the latest released version.

## Reporting a Vulnerability

Please report security issues privately before opening a public issue.

Until a dedicated security contact is published, open a GitHub security advisory
or contact the maintainer through the repository owner profile.

Please include:

- affected version or commit
- minimal reproduction
- expected impact
- whether the issue is exploitable remotely

## Security Scope

`flowbrigade` provides flow-control utilities. It is not an authentication,
authorization, or access-control framework.

The library is designed to avoid common misuse risks:

- duration parsing rejects oversized inputs by default
- duration parsing checks integer overflow
- invalid limiter configuration is rejected early
- invalid request costs are rejected early
- keyed in-memory limiters have a configurable maximum key count
- in-memory rate limit storage has a configurable maximum key count
- stored limiters reject blank keys and oversized keys
- stored limiters reject control characters in keys and prefixes
- stored limiters can clear a single key for operational recovery
- rate limit keys can be built through validated key builders
- external storage can be wrapped as fail-closed or fail-open
- stored limiters support audit callbacks for application logging or metrics
- expired keyed limiter entries are pruned before enforcing key capacity
- expired in-memory storage entries are pruned before enforcing key capacity
- retry helpers do not catch `Defect`

## Operational Limits

In-memory limiters are process-local. They do not enforce limits across multiple
processes, machines, or service replicas. Use a distributed store or gateway when
limits must be enforced globally.

`RateLimitStorage` is an adapter boundary. External storage adapters must make
their consuming operations atomic if they are used across processes or machines.
The core in-memory storage adapter is intended for tests and single-process use.
The official Redis adapter uses Lua scripts so fixed-window and token-bucket
consume operations are atomic within Redis.
The Memcached adapter requires real `gets`/`cas` semantics from the chosen
client before it should be treated as distributed-safe.

Mutable limiter, throttle, debounce, timeout, and circuit breaker objects do not
provide internal locking. Protect shared instances with synchronization when
using them across threads.

Jitter uses non-cryptographic randomness. It is intended only to spread retry
timing and must not be used for security-sensitive randomness.

`Timeout` tracks elapsed time. It does not cancel running work by itself.

## Denial-of-Service Considerations

Use the default duration input length limit unless there is a clear reason to
increase it.

For untrusted keys such as IP addresses, user agents, or request parameters,
configure `maxKeys` on keyed limiters according to the memory budget of the
process. Apply the same rule to `InMemoryRateLimitStorage` when using stored
limiters.

Stored limiters also enforce `maxKeyLength`, defaulting to 512 bytes. Do not use
raw unbounded request data as keys. Prefer stable identifiers such as a user id,
API token hash, normalized route name, or trusted client identity.
Control characters are rejected to keep storage keys, logs, and metrics easier
to reason about.

Use `clear` carefully. It is useful for administrative recovery, but exposing it
to untrusted users would allow them to bypass rate limits.

Prefer `rateLimitKey` or `opaqueRateLimitKey` instead of ad hoc string
concatenation for keys. When keys include sensitive identifiers such as email
addresses or API tokens, use `opaqueRateLimitKey` with an application-provided
hash or HMAC function.

For external storage failures, `failClosed` is safer for protected resources
because it denies when storage is unavailable. `failOpen` preserves availability
but may allow traffic that would otherwise be limited. Choose deliberately per
endpoint or workload.

Audit callbacks are intended for application-owned logging and metrics. Avoid
recording raw sensitive identifiers in audit logs.

For public HTTP services, combine in-process flow control with deployment-level
controls such as reverse proxy limits, request size limits, connection limits,
and distributed rate limiting when needed.

FlowBrigade can help return consistent `RateLimit-*` and `Retry-After` headers,
but it is not a complete DDoS protection layer. Volumetric attacks should be
handled before application code when possible.

## Adapter Security

Do not expose Redis or Memcached directly to untrusted networks for FlowBrigade
usage. Keep storage services on trusted networks, configure authentication when
available, and apply provider-specific hardening outside this library.

Client bridge packages are responsible for converting provider errors into
clear application errors. Applications are still responsible for connection
timeouts, credentials, network policy, and deployment-level access control.
