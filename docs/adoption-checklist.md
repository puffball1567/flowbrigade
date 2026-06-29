# Adoption checklist

Use this checklist when deciding whether FlowBrigade is ready for a project.

## Fit

- The project needs flow control: retry, backoff, rate limiting, throttling,
  circuit breaking, bulkheads, reservations, or simple locks.
- Calendar, timezone, localization, and date formatting are not required from
  this package.
- Framework-specific middleware is not required from the core package.
- The application can translate FlowBrigade decisions into its own framework or
  transport layer.

## First integration

- Pick one limiter or retry policy first.
- Add a dependency-free recipe to the application test suite.
- Use direct limiter objects before adding a registry.
- Add `LimiterRegistry` only when names/configuration are useful.
- Use `httpLimitDecision` only at framework boundaries.

## Storage

- Keep in-memory limiters for single-process use.
- Use Redis or another storage adapter when limits must be shared.
- Check capabilities with `requireCapabilities`.
- Do not assume `rlcReservation` unless the adapter advertises it.
- Do not treat Memcached as distributed-safe unless the chosen client provides
  real `gets`/`cas` behavior.

## Failure behavior

- Choose `failClosed` for abuse prevention and security-sensitive limits.
- Choose `failOpen` for non-critical limits where availability matters more.
- Log or count storage failures through application observability.
- Test both storage-success and storage-failure paths.

## Key safety

- Use stable keys.
- Reject or normalize untrusted parts before building keys.
- Use `rateLimitKey` or `KeyExtractor` rather than manual concatenation.
- Use `opaqueRateLimitKey` when keys contain personal data or secrets.
- Set bounded key capacity for in-memory keyed limiters.

## Release readiness

- Core tests pass.
- Snippets and recipes pass.
- Integration tests either pass or print a clear `SKIP:` reason.
- API docs build.
- Security scope is understood.
- Adapter responsibility boundaries are understood.

## What FlowBrigade does not replace

- Authentication
- Authorization
- Complete DDoS protection
- WAF or edge gateway rules
- Transport encryption
- Password hashing
- Full queue/failure transport systems
- Production Redis or Memcached hardening
