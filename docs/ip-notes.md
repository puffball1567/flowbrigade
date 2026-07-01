# Intellectual Property Notes

This document records engineering due-diligence notes for algorithms and
operational patterns used by FlowBrigade. It is not legal advice.

## Standards and Common Operational Patterns

FlowBrigade may implement algorithms or control patterns that are publicly
described in standards, books, operational guides, or long-standing OSS
practice. Implementations must be written for FlowBrigade's own API and tests,
without copying code from other OSS projects.

## GCRA

Before adding the GCRA-style limiter, the project reviewed public descriptions
of the Generic Cell Rate Algorithm and searched Google Patents for obvious
direct matches using terms such as:

- `Generic Cell Rate Algorithm`
- `GCRA`
- `Theoretical Arrival Time`
- `ITU-T I.371`
- `ATM Forum`

The review found GCRA described as an ATM/ITU-T/ATM Forum traffic policing and
shaping algorithm based on theoretical arrival time and continuous-state leaky
bucket descriptions. No obvious direct Google Patents result blocking a
standard GCRA-style in-process limiter was found during this review.

The review also found existing OSS usage of GCRA-style rate limiting, including
Rust's `governor` crate and the `redis-cell` Redis module. These projects were
treated as evidence that GCRA is a commonly used public algorithmic approach,
not as implementation sources to copy from.

The FlowBrigade implementation is an independent GCRA-style limiter written
against the public algorithmic description and FlowBrigade's `RateLimitResult`
API. It is not copied from another OSS implementation.

## Retry Allowance

Before adding `RetryAllowance`, the project reviewed public usage of retry
budget style controls and searched Google Patents for obvious direct matches
using terms such as:

- `retry budget`
- `retry storm budget`
- `external service guard retry rate limit circuit breaker`
- `service guard circuit breaker rate limit`

The review found retry budget style controls in established resilience tooling,
including Finagle's `RetryBudget`, where retry budgets are documented as a way
to prevent retry storms. These projects were treated as evidence that the
pattern is commonly used, not as implementation sources to copy from.

FlowBrigade intentionally exposes this feature as `RetryAllowance` rather than
copying another library's API name or shape. The implementation records original
work and retry consumption using FlowBrigade's own keyed window state and result
types.

## Contact and Remediation

If you believe FlowBrigade includes code or behavior that infringes your rights,
please contact the maintainer with enough detail to review the claim. The
project will respond in good faith and may modify, disable, or remove the
affected implementation while the concern is investigated.
